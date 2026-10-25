#!/usr/bin/env bash
# Deploy Clubhouse 3 to AWS (amazon.clubhouse3.dev): build the image, push it to ECR,
# register task-definition.json with that image, run the migrations, roll the service.
#
#   deploy/aws/deploy.sh [--no-cache]
#
# Needs Docker Desktop and the aws CLI on account 407444941814. Arguments go to
# docker build: --no-cache rebuilds every layer, which is how the apt-get upgrade
# in the Dockerfile picks up new Debian fixes. A failed migration leaves the
# service on its current revision.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ACCOUNT=407444941814
export AWS_REGION=us-west-2 AWS_PAGER=""
CLUSTER=clubhouse3
SERVICE=clubhouse3-web
LOG_GROUP=/ecs/clubhouse3
REPO=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/clubhouse3
CONTEXT=${DOCKER_CONTEXT:-desktop-linux}
D="docker --context $CONTEXT"

# Build and push from this machine only: never a context that reaches another host,
# such as the one for the beta server.
case "$(docker context inspect "$CONTEXT" --format '{{.Endpoints.docker.Host}}')" in
  unix://* | npipe://*) ;;
  *) echo "Docker context $CONTEXT is not a local daemon; refusing." >&2; exit 1 ;;
esac
if [ "$(aws sts get-caller-identity --query Account --output text)" != "$ACCOUNT" ]; then
  echo "The aws CLI is not on account $ACCOUNT; refusing." >&2
  exit 1
fi

TAG=$(git rev-parse --short HEAD)
[ -z "$(git status --porcelain)" ] || TAG="$TAG-uncommitted-$(date +%Y%m%d%H%M)"

echo "== Building $REPO:$TAG"
$D build --pull --platform linux/arm64 "$@" -t "$REPO:$TAG" -t "$REPO:latest" .
aws ecr get-login-password | $D login --username AWS --password-stdin "${REPO%%/*}"
$D push "$REPO:$TAG"
$D push "$REPO:latest"

# Each revision names its own image, so rolling back is pointing the service at
# the previous revision.
echo "== Registering task-definition.json with $TAG"
TASK_DEF=$(aws ecs register-task-definition \
  --cli-input-json "$(jq --arg image "$REPO:$TAG" '.containerDefinitions[0].image = $image' deploy/aws/task-definition.json)" \
  --query 'taskDefinition.taskDefinitionArn' --output text)
echo "${TASK_DEF##*/}"

# Booting for db:migrate also proves the new image starts before any traffic reaches it.
echo "== Migrating"
NET=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --query 'services[0].networkConfiguration' --output json)
TASK=$(aws ecs run-task --cluster $CLUSTER --launch-type FARGATE --task-definition "$TASK_DEF" \
  --network-configuration "$NET" --started-by deploy-migrate \
  --overrides '{"containerOverrides":[{"name":"web","command":["bin/rails","db:migrate"]}]}' \
  --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-stopped --cluster $CLUSTER --tasks "$TASK"
CODE=$(aws ecs describe-tasks --cluster $CLUSTER --tasks "$TASK" --query 'tasks[0].containers[0].exitCode' --output text)
if [ "$CODE" != 0 ]; then
  echo "db:migrate exited $CODE ($(aws ecs describe-tasks --cluster $CLUSTER --tasks "$TASK" --query 'tasks[0].stoppedReason' --output text))." >&2
  aws logs tail $LOG_GROUP --log-stream-names "web/web/${TASK##*/}" --since 1h >&2 || true
  echo "The service was left on its current revision." >&2
  exit 1
fi

echo "== Rolling $SERVICE"
aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition "$TASK_DEF" > /dev/null
aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE
# The circuit breaker rolls a failed deployment back, and the service then settles on the old revision.
RUNNING=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --query 'services[0].taskDefinition' --output text)
if [ "$RUNNING" != "$TASK_DEF" ]; then
  echo "The deployment was rolled back to ${RUNNING##*/}. See: aws logs tail $LOG_GROUP --since 30m" >&2
  exit 1
fi
echo "Deployed $TAG as ${TASK_DEF##*/}"
