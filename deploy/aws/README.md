# AWS deployment

Clubhouse 3 at <https://amazon.clubhouse3.dev>, running alongside the beta at clubhouse3.dev with a
database of its own. ECS Fargate (arm64) in us-west-2, account 407444941814, behind an Application
Load Balancer that only Cloudflare can reach; RDS MariaDB 12.3 over TLS; S3 for Active Storage; SES
for mail.

| File | What it is |
|---|---|
| `deploy.sh` | Builds and pushes the image, registers `task-definition.json` with it, runs `db:migrate` as a one-off task, then rolls the `clubhouse3-web` service. |
| `task-definition.json` | The app. Its environment lives here: edit it and deploy. `image` is replaced at deploy with the build's own tag. Secrets are SSM parameters under `/clubhouse3/`. |
| `dbshell-task-definition.json` | A `mariadb` container that sleeps for an hour, for port-forwarding to RDS. Register it by hand after a change: `aws ecs register-task-definition --cli-input-json file://deploy/aws/dbshell-task-definition.json`. |

Needs Docker Desktop, `jq`, the AWS Session Manager plugin (for the database), and the aws CLI on
account 407444941814 with the `clubhouse3-cli` policy.

**Deploy:** `deploy/aws/deploy.sh`. Add `--no-cache` now and then so the image picks up new Debian
fixes. The deploy refuses a Docker context that isn't local, so it can never reach the beta server.

**Roll back:** point the service at the previous revision, which carries the previous image:
`aws ecs update-service --cluster clubhouse3 --service clubhouse3-web --task-definition clubhouse3-web:<N>`

**Reach the database:** RDS has no public address. Start a database shell and forward a local port
through it:

```bash
NET=$(aws ecs describe-services --cluster clubhouse3 --services clubhouse3-web --query 'services[0].networkConfiguration' --output json)
TASK=$(aws ecs run-task --cluster clubhouse3 --launch-type FARGATE --task-definition clubhouse3-dbshell --enable-execute-command --network-configuration "$NET" --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-running --cluster clubhouse3 --tasks $TASK   # then about 20 s more for the exec agent
RUNTIME=$(aws ecs describe-tasks --cluster clubhouse3 --tasks $TASK --query 'tasks[0].containers[0].runtimeId' --output text)
aws ssm start-session --target "ecs:clubhouse3_${TASK##*/}_$RUNTIME" --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["clubhouse3.cit7gvsupthj.us-west-2.rds.amazonaws.com"],"portNumber":["3306"],"localPortNumber":["13306"]}'
```

Then, in another shell, connect as the app's user. Its password is the `/clubhouse3/RANGER_DB_PASSWORD`
parameter; the admin's is in the RDS-managed secret.

```bash
MYSQL_PWD=$(aws ssm get-parameter --name /clubhouse3/RANGER_DB_PASSWORD --with-decryption --query Parameter.Value --output text) \
  mariadb -h 127.0.0.1 -P 13306 --protocol=TCP -u clubhouse clubhouse
```

Ctrl-C ends the forward. Stop the shell with `aws ecs stop-task --cluster clubhouse3 --task $TASK`,
or let it stop itself after an hour.
