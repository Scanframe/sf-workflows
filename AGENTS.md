# AGENTS.md — Guidelines for AI Agents Working on This Project

This file documents key architectural decisions and patterns to prevent common mistakes when modifying the CI runner configuration.

## Runner Isolation Pattern & Docker-outside-of-Docker (DooD)

The GitHub and GitLab runners support multiple instances via the `-s` / `--suffix` flag (e.g., `-s '-01'`, `-s '-02'`).

### How isolation and container jobs work

Runners communicate with the host Docker daemon via `/var/run/docker.sock` (Docker-outside-of-Docker). When a workflow job executes inside a container (using `container:` or container-based actions), the runner inside the container instructs the host Docker daemon to mount its workspace into the job container at `/__w`.

Because the host Docker daemon resolves volume mount source paths on the **host filesystem**:
- The path inside the runner container **MUST match the host-side path**.
- Suffixes must be applied to **both host and container sides** of the workspace volume mount:
  `/tmp/runner${GITHUB_RUNNER_SUFFIX}:/tmp/runner${GITHUB_RUNNER_SUFFIX}`
- `RUNNER_WORKDIR` must point to `/tmp/runner${GITHUB_RUNNER_SUFFIX}/work`.

### Why container-side paths MUST have matching suffixes

If the host path was `/tmp/runnerexport-01` but mapped to `/tmp/runner` in the runner container:
1. The runner writes job files (command files, save_state, scripts) to `/tmp/runner/work` inside its container (physically on host at `/tmp/runnerexport-01/work`).
2. When starting a container job, the runner tells the host Docker daemon: `docker create -v /tmp/runner/work:/__w ...`.
3. The host Docker daemon mounts `/tmp/runner/work` from the host (not `/tmp/runnerexport-01/work`).
4. The job container sees an empty `/__w` directory and fails with:
   `Error: Missing file at path: /__w/_temp/_runner_file_commands/save_state_...`.

### What IS suffixed

- Docker Compose project name: `github-runner${GITHUB_RUNNER_SUFFIX}`
- Container name: `${GITHUB_RUNNER_NAME}${GITHUB_RUNNER_SUFFIX}`
- Runner name: `${GITHUB_RUNNER_NAME}${GITHUB_RUNNER_SUFFIX}`
- Host-side volume paths: `/tmp/runner${GITHUB_RUNNER_SUFFIX}`
- Container-side mount points for workspace: `/tmp/runner${GITHUB_RUNNER_SUFFIX}`
- `RUNNER_WORKDIR`: `/tmp/runner${GITHUB_RUNNER_SUFFIX}/work`

### Fixed Paths

- Runner externals: `/actions-runner/externals:/actions-runner/externals` (shared read-only runtime binaries node20/node24 across all runners).

## Volume vs Environment Variable Distinction

- **Volume mounts** control where data lives on the **host** and where it appears inside the **container**.
- **Environment variables** like `RUNNER_WORKDIR` control where the runner **process** writes its work inside the **container**.

`RUNNER_WORKDIR` must point to a path inside the mounted volume matching the host directory so work data persists and sibling container jobs resolve the correct path.

## Network Mode

Runners use `network_mode: host`, meaning containers share the host's network namespace. When adding features, ensure no fixed port conflicts arise between multiple runner instances.

## Secret Handling

- `GITHUB_PAT` in `.env` is a real personal access token. **Do not expose it in logs, error messages, or responses.**
- The `.env` file is git-ignored. Never commit it.
