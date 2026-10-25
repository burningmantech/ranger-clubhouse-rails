# Clubhouse 3

The Black Rock Rangers' volunteer coordination application: Ruby 4.0, Rails 8.1, MariaDB 12.3,
Hotwire, Tailwind CSS 4 and daisyUI 5. It replaces Clubhouse 2 (`ranger-clubhouse-api` and
`ranger-clubhouse-web`).

## Development

```bash
bin/setup        # gems, npm packages, database
bin/dev          # Rails on :3000 plus the Tailwind watcher
bin/rails test   # the suite; bin/rails test:all adds the system tests (headless Chrome)
bin/rubocop && bin/brakeman && ruby bin/css_lint.rb --strict && bin/importmap audit
```

Development signs in without a password through `GET /sign-in-as`. `AGENTS.md` holds the
conventions, and `docs/FEATURES.md` maps every page to its route, owner, tables and tests.

## Deployment

Clubhouse 3 runs on AWS ECS Fargate in the `rangers` cluster, like the rest of the Ranger
services, as `ranger-clubhouse-staging-fg` and `ranger-clubhouse-production-fg`. It takes over
Clubhouse 2's hostnames; nothing changes in DNS.

Deploys happen only through GitHub Actions (`.github/workflows/`):

1. **Every pull request** runs Lint, Tests and Build Docker image. `main` takes nothing but a pull
   request with those three checks green, with no bypass.
2. **A merge to `main`** runs them again, pushes the image to ECR as `:<sha>` and `:staging`, migrates
   the staging database with a one-off task, and rolls the staging service (`deploy-staging` in
   `cicd.yml`). Check your change at the staging hostname.
3. **Deploy to production** is a workflow you run by hand from the Actions tab (`deploy.yml`). It
   promotes the exact image staging runs, by digest, migrates, and rolls the production service.
   Only the accounts listed in its `Check user` step may run it.

The task definitions live in AWS and hold the environment; a deploy changes only the image, so
**rolling back** is pointing the service at the previous task-definition revision:

```bash
aws ecs update-service --cluster rangers --service ranger-clubhouse-production-fg --task-definition ranger-clubhouse-production-fg:<N>
```

Each service's database is reachable only from inside the VPC: run a one-off task in the cluster
and port-forward through Session Manager. The beta at `clubhouse3.dev` and the deployment under
`deploy/aws/` are separate from all of this and are deployed by hand.

The deploy jobs are commented out in both workflows until the AWS resources exist; the checklist
is in the project's issue tracker (`.scratch/github-cicd/PRD.md`).
