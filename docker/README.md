# Self-Hosted GitHub Actions Runner

This directory contains a Docker Compose setup for running a self-hosted GitHub Actions runner with
Docker-in-Docker support.

## Prerequisites

- Docker and Docker Compose installed on the host machine
- Access to register runners on the GitHub organization or repository

## Setup

### 1. Generate a runner registration token

Go to the new runner page of the repository (requires admin access to it):

[https://github.com/scanframe-org/sf-gitlab-devops/settings/actions/runners/new](https://github.com/scanframe-org/sf-gitlab-devops/settings/actions/runners/new)

Select **Linux** → **x64**, then copy only the **registration token**: the value after `--token` in the
`./config.sh --url ... --token XXXX` line. The token expires after 1 hour, so use it promptly.

> **Do not install the runner on the host** and do not run the `download`/`config.sh` commands shown on that page.
> The Docker image already contains the runner and runs `config.sh` inside the container with the token from `.env`.
> The page is only used as a place to read the token.

### 2. Create the environment file

Copy the example environment file and fill in your token:

```bash
cp .env.example .env
```

Edit `.env` and replace `your-registration-token-here` with the token you just copied.

### 3. Start the runner

```bash
docker compose up -d
```

The container will register itself with GitHub and start listening for jobs.

### 4. Configure the runner scope

The `docker-compose-org.yml` file supports two modes. Edit the file before starting the runner:

**Repository runner** (default, single repo only):

```yaml
RUNNER_SCOPE: repo
REPO_URL: https://github.com/scanframe-org/sf-gitlab-devops
```

`REPO_URL` restricts the runner to that one repository.

**Organization runner** (only when the repos are in a GitHub organization):

```yaml
RUNNER_SCOPE: org
ORG_NAME: Scanframe
```

The organization runners page is `https://github.com/organizations/<org>/settings/actions/runners` and only exists for real organizations.

### 5. Verify the runner

Check the runner appears online at:

`https://github.com/scanframe-org/sf-gitlab-devops/settings/actions/runners`

The runner `sf-build-01` should show as **Online**.

## Using the Runner

Reference the custom label in your workflow files:

```yaml
jobs:
  build:
    runs-on: [ sf-build ]
```

## Configuration

| Setting               | Value       | Description                                                         |
|-----------------------|-------------|---------------------------------------------------------------------|
| `RUNNER_SCOPE`        | `repo`      | `repo` for a single repository, `org` for an organization           |
| `REPO_URL`            | repo URL    | Full repository URL (required for repo scope)                       |
| `LABELS`              | `sf-build`  | Custom label for workflow targeting                                 |
| `EPHEMERAL`           | `true`      | Auto-unregister after each job; re-registers on container restart   |
| `DISABLE_AUTO_UPDATE` | `true`      | Prevents runner binary auto-updates; control version via image tag  |
| `UNSET_CONFIG_VARS`   | `true`      | Removes config env vars after registration to avoid leaking secrets |

### Volumes

- `/var/run/docker.sock` — Docker socket for Docker-in-Docker (required for `--privileged` build
  jobs)
- `/tmp/runner` — Work directory (must match host and container paths)

## Monitoring Logs

The runner logs show registration status, job assignments, and any errors.

### Live logs (follow mode)

Watch the runner output in real time:

```bash
docker compose logs -f runner
```

### Recent logs

Show the last 100 lines:

```bash
docker compose logs --tail=100 runner
```

### Logs for a specific time range

Show logs from the last hour:

```bash
docker compose logs --since 1h runner
```

### Checking runner status

1. **Container status**: Verify the container is running:
   ```bash
   docker compose ps
   ```
2. **GitHub dashboard**: Check the runner appears online at:
   `https://github.com/scanframe-org/sf-gitlab-devops/settings/actions/runners`
   The runner `sf-build-01` should show as **Online** with a green dot.
3. **Job history**: View completed and in-progress jobs on the same page under the runner list.

## Container jobs (`container:` in a workflow)

The runner uses the host Docker daemon through the socket. For jobs with `container:` the runner mounts its
`externals` directory (with `node24`) into the job container as `/__e`. The daemon resolves that path on the
**host**, so it must exist there. Otherwise `actions/checkout` fails with
`exec: "/__e/node24/bin/node": no such file or directory`.

Populate the host directory once (and again after updating the runner image):

```bash
sudo mkdir -p /actions-runner
id=$(docker create myoung34/github-runner:latest)
sudo rm -rf /actions-runner/externals
sudo docker cp "$id":/actions-runner/externals /actions-runner/externals
docker rm "$id"
docker compose up -d --force-recreate
```

The compose file bind mounts `/actions-runner/externals` at the identical path, because the host daemon resolves the
source path the runner reports (its own `/actions-runner/externals`) on the host.

## Non-root runner (`RUN_AS_ROOT: "false"`)

The runner process runs as user `runner` (uid 1001), the same as the GitHub-hosted runners. The workspace is then
owned by uid 1001 instead of root. The build image entrypoint takes the build user uid:gid from the workspace owner
and fails with `usermod: UID '0' already exists` when the workspace is owned by root.

When switching from a root runner, remove the root-owned work directory on the host once:

```bash
sudo rm -rf /tmp/runner/work
docker compose up -d --force-recreate
```

## Token Expiration

The runner registration token from GitHub expires after 1 hour. With `EPHEMERAL: true` (default),
the runner unregisters after each job and re-registers on container restart. This means you need a
fresh token each time you restart the container.

**For a persistent runner** (no re-registration on restart):

1. Remove `EPHEMERAL: "true"` from `docker-compose-org.yml`.
2. Uncomment the `/runner/data` volume mount in `docker-compose-org.yml`.
3. The runner will persist its registration and survive restarts without needing a new token.

## Troubleshooting

- **Registration failed**: Ensure the token is copied correctly and hasn't expired (tokens expire
  after 1 hour). Generate a fresh token from the GitHub UI and update `.env`.
- **Runner not appearing**: Check that `ORG_NAME` or `REPO_URL` matches exactly. Look at the logs
  for registration errors: `docker compose logs runner | grep -i error`.
- **Docker commands fail in jobs**: Ensure the Docker socket volume mount is present and the host
  Docker daemon is running.
- **Runner offline**: Restart the container with `docker compose restart runner` and check logs for
  connection issues.
- **Stale runner**: If the runner shows as offline with a red "X", remove and recreate it:
  `docker compose down` then `docker compose up -d`.
