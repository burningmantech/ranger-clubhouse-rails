# Clubhouse 3

The Black Rock Rangers' volunteer coordination application: Ruby 4.0, Rails 8.1, MariaDB 12.3,
Hotwire, Tailwind CSS 4 and daisyUI 5. It replaces Clubhouse 2 (`ranger-clubhouse-api` and
`ranger-clubhouse-web`).

## Development

```bash
bin/setup        # gems and database, then starts bin/dev (--skip-server to stop short)
bin/dev          # Rails on :3000 plus the Tailwind watcher
bin/rails test   # the suite; bin/rails test:all adds the system tests (headless Chrome)
bin/rubocop && bin/brakeman && ruby bin/css_lint.rb --strict && bin/importmap audit
```

Development signs in without a password through `GET /sign-in-as`. `AGENTS.md` holds the
conventions, and `docs/FEATURES.md` maps every page to its route, owner, tables and tests.

## Deployment

Clubhouse 3 runs on AWS ECS Fargate in the `rangers` cluster, like the rest of the Ranger
services, as `ranger-clubhouse-rails-staging-fg` and `ranger-clubhouse-rails-production-fg`. It takes over
Clubhouse 2's hostnames; nothing changes in DNS.

Deploys happen only through GitHub Actions (`.github/workflows/`):

1. **Every pull request** runs Lint, Tests, System tests and Build Docker image. `main` takes nothing
   but a pull request with those four checks green, with no bypass.
2. **A merge to `main`** runs them again, pushes the image to ECR as `:<sha>`, rolls the staging service
   to it by digest (`deploy-staging` in `cicd.yml`) and, once the roll is stable, points `:staging` at it.
   Check your change at the staging hostname.
3. **Deploy to production** is a workflow you run by hand from the Actions tab (`deploy.yml`). It
   reads the image and commit from the staging service's task definition, so it promotes exactly
   what staging runs, by digest, and rolls the production service. Only the accounts in its
   `DEPLOYERS` list at the top of the file may run or re-run it.

Both workflows migrate the database inside the new task definition: a `migrate` container runs
`bin/rails deploy:migrate` and the web container starts only once it exits cleanly. That happens on every
task launch, so with nothing pending it is a short boot and exit. A failed migration stops each new
task before it serves; after three, the service rolls back and the deploy fails. The old tasks serve
throughout, so a migration must still work beside the release before it: rename a table or column
over two deploys, never one. The migration's output is the `ecs/migrate/<task id>` stream in the
service's log group.

`deploy:migrate` is `db:migrate` with three guards (`lib/deploy_migration_guard.rb`). MariaDB keeps
whatever part of a failed migration ran, so a migration that started and never finished is not run
again by the relaunches. A statement waits 30 seconds at most for a table lock, since an `ALTER`
waiting behind an open transaction holds up every query on that table. A second runner waits for the
first instead of failing. After a failed migration, repair the database by hand, delete the marker,
then re-run the deploy:

```sql
DELETE FROM ar_internal_metadata WHERE `key` = 'deploy_migration_started';
```

**Restoring a database** on AWS, the Clubhouse 2 cutover included, starts with the service's desired
count at 0, because any task launch migrates. Follow the order in `docker-compose.yml`, run its
migration step as a one-off task with the command `bin/rails deploy:migrate`, and scale the service
back up only once `BroadcastMailSandbox` is back on.

The image runs nginx in front of Puma (`docker/nginx/`, started together by `bin/docker-server`): it
refuses probes and overwrites the forwarded headers before Rails sees a request, and
`docker/nginx/check.sh`, which CI runs inside the built image, proves each rule.

The task definitions live in AWS and hold the environment; a deploy changes only the image and
rebuilds the `migrate` container from the web container, so **rolling back** is pointing the service
at the previous task-definition revision:

```bash
aws ecs update-service --cluster rangers --service ranger-clubhouse-rails-production-fg --task-definition ranger-clubhouse-rails-production-fg:<N>
```

Production promotes whatever staging's completed deployment runs, so rolling staging back also
changes what the next production deploy ships.

Each service's database is reachable only from inside the VPC: run a one-off task in the cluster
and port-forward through Session Manager. The beta at `clubhouse3.dev` and the deployment under
`deploy/aws/` are separate from all of this and are deployed by hand.
