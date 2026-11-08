# Central CI-Pipeline Configurations

## GitHub Actions CI

This directory holds a reusable GitHub Actions pipeline that can be called from many projects.

- `workflows/ci.yml` is the reusable workflow (`on: workflow_call`).
- `actions/build-job` and `actions/deploy-job` are the composite actions used by the workflow.

Each project only needs a small caller workflow.
The pipeline is the equivalent of the GitLab pipeline in `gitlab-ci/` without the `SF_SIGNAL` testing capabilities.

### Jobs

| Job              | Description                                                                          |
|------------------|--------------------------------------------------------------------------------------|
| `check-env`      | Prints the environment and runs `check-format.sh` when present.                      |
| `build`          | Matrix job building and packaging every toolchain (default: gnu, gw, ga and msvc).   |
| `linux-gcov`     | Coverage build (`gnu-coverage`) for PRs and manual runs. Publishes the report to the Nexus exchange repo, writes `report.txt` to the job summary and comments a link to the report on same-repo PRs. |
| `deploy-develop` | Automatic deploy to Nexus for every branch except the release branch.                |
| `deploy-staging` | Manual deploy from the release branch (environment `staging`).                       |
| `deploy-stable`  | Manual deploy from the release branch (environment `stable`).                        |

### Using it in a project

#### 1. Project requirements

The pipeline relies on this contract in the calling project:

- `build.py` with the `native`, `wine` and `publish` commands.
- CMake workflow presets named `<toolchain>-release` (for example `gnu-release`) and `gnu-coverage`.
- Optionally `check-format.sh` in the root, which is executed when it exists.
- Git version tags, since the build runs `git describe`. The build jobs check out the full history including tags.
- Build output in `bin/pkg` (packages) and `bin/gcov` (coverage `report.*`) and binaries in the `bin-dir` of the matrix.

#### 2. Caller workflow

Add `.github/workflows/ci.yml` to the project. Replace `<owner>/<central-repo>` with the location of this repository.

```yaml
name: CI

# Cancel in-progress runs on the same ref when there is a new commit.
# This must be in the caller. In the called workflow it would cancel itself.
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

on:
  push:
    branches: ['**']
  pull_request:
  workflow_dispatch:
    inputs:
      deploy:
        description: 'Manual deploy of the packages (only from the release branch)'
        type: choice
        default: none
        options: [none, staging, stable]

jobs:
  ci:
    # A called workflow can not get more permissions than the caller grants.
    permissions:
      contents: read
      pull-requests: write
    uses: <owner>/<central-repo>/.github/workflows/ci.yml@v1
    secrets: inherit
    with:
      deploy: ${{ inputs.deploy || 'none' }}
```

The triggers, the `deploy` choice input and `concurrency` live in the caller, because only the triggers of the caller start a run.

#### 3. Optional inputs

All inputs have defaults reproducing the standard pipeline, so overriding them is optional.

| Input            | Type    | Default                                          | Description                                                               |
|------------------|---------|--------------------------------------------------|---------------------------------------------------------------------------|
| `deploy`         | string  | `none`                                           | `none`, `staging` or `stable`. Manual deploy from the release branch.      |
| `docker-image`   | string  | `nexus.scanframe.com/amd64/gnu-cpp:24.04-6.12.0` | Container image the jobs run in.                                           |
| `matrix`         | string  | gnu, gw, ga and msvc                             | JSON object with an `include` list of toolchains.                          |
| `coverage`       | boolean | `true`                                           | Enables the `linux-gcov` job.                                              |
| `release-branch` | string  | empty                                            | Release branch. Falls back to variable `SF_RELEASE_BRANCH`, then `main`.   |

Example overriding the matrix and disabling coverage:

```yaml
    with:
      deploy: ${{ inputs.deploy || 'none' }}
      coverage: false
      matrix: >-
        {"include":[
        {"name":"linux-gnu","toolchain":"gnu","build-cmd":"./build.py native","bin-dir":"bin/lnx64"}
        ]}
```

Each matrix entry needs the keys `name`, `toolchain`, `build-cmd` and `bin-dir`.
The build command executed is `<build-cmd> --workflow "<toolchain>-release"`.

#### 4. Secrets, variables and environments

Configure these in the calling repository or on organization level (organization secrets avoid repeating them per project):

- **Secrets** (passed by `secrets: inherit`): `NEXUS_USER`, `NEXUS_PASSWORD`, `NEXUS_SERVER_URL`, `NEXUS_RAW_REPO`,
  `NEXUS_EXCHANGE_REPO` and `NEXUS_WINGET_REFRESH`. All are declared optional in the workflow.
- **Variable** (optional): `SF_RELEASE_BRANCH`, the branch allowing `staging` and `stable` deploys (default `main`).
- **Environments**: `staging` and `stable`. Environment secrets override the repository secrets when the Nexus targets differ.
  Required reviewers on an environment give an approval step before a deploy.

#### 5. Container image and runners

The jobs run in the container image from the `docker-image` input, which by default is hosted on the Nexus server.
The image must be pullable from the runner executing the project's jobs.
Use a self-hosted runner that can reach the registry, or pick a public image using `docker-image`.
The build jobs run with `--privileged`.

The workflow uses `runs-on: ${{ fromJSON(vars.SF_RUNNER_LABELS || '["ubuntu-latest"]') }}`.
A `runs-on` list is not a fallback: a runner must have *all* listed labels. GitHub has no automatic fallback.
By default the GitHub-hosted `ubuntu-latest` runner is used. To use the self-hosted runner, set the repository or
organization variable `SF_RUNNER_LABELS` to `["sf-build"]`. Remove the variable to go back to GitHub-hosted.
Set up the self-hosted runner using the Docker Compose configuration in `docker/`.

### Versioning

The workflow references the composite actions with a tag: `<owner>/<central-repo>/.github/actions/<name>@v1`.
A `uses:` path can not be dynamic, so the version is fixed in `workflows/ci.yml`.

- Callers pin the workflow with `@v1`, and the workflow pins the actions with `@v1`.
- Release the workflow and the actions together under the same tag to prevent version skew.
- For backward compatible changes move the `v1` tag to the new commit:

  ```bash
  git tag -f v1 && git push -f origin v1
  ```

- For breaking changes create a new major tag such as `v2` and change the `@v1` references of the actions in `workflows/ci.yml` to `@v2` in that release.
  Projects switch when they change their caller to `@v2`.
- When testing a branch, temporarily change the action references in `workflows/ci.yml` and the caller to the branch name.

### Notes

- This repository can not run the workflow itself without a caller. Test using a project calling it.
- Pull requests from forks have no access to secrets. Deploys are skipped for them.
- YAML anchors in `workflows/ci.yml` only work within that file. GitHub supports anchors since September 2025,
  so older GitHub Enterprise Server versions may reject the file.


### GitLab CI-pipelines

> Readme needs implementation.