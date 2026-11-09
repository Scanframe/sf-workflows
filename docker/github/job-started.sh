#!/usr/bin/env bash
# Runner job-started hook (ACTIONS_RUNNER_HOOK_JOB_STARTED), runs as user 'runner' before every job.
# Gives each job an empty workspace like a GitHub-hosted runner. The workspace on the host keeps files from
# earlier jobs, and files created as root by container jobs can not be overwritten by the non-root runner
# (e.g. 'actions/download-artifact' failing to extract). User 'runner' has passwordless sudo in the image.
set -euo pipefail

if [[ -n "${GITHUB_WORKSPACE:-}" && -d "${GITHUB_WORKSPACE}" ]]; then
	echo "Clearing workspace '${GITHUB_WORKSPACE}'."
	sudo find "${GITHUB_WORKSPACE}" -mindepth 1 -delete
fi
