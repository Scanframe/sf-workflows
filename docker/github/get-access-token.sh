#!/usr/bin/env bash
# Bailout on first error.
set -e

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Form the environment file.
env_file="${script_dir}/.env"

if [[ -z "$1" ]]; then
	echo "Usage: $0 <organisation-name> <fine-grained-pat>

  Requests a fresh runner registration token for the scanframe-org organisation.
  The argument is a fine-grained PAT (github_pat_...) created by an org owner with
  'Self-hosted runners: Read and write' under Organization permissions.

  Use '--' as organisation name to read arguments from file: ${env_file}
"
	exit 0
fi

if [[ "$1" == "--" ]]; then
	if [[ ! -f "${env_file}" ]]; then
		echo "File environment file not found!: ${env_file}"
		exit 1
	fi
	# shellcheck disable=SC1090
	source "${env_file}"
	org="${GITHUB_ORG}"
	pat="${GITHUB_PAT}"
else
	org="$1"
	pat="$2"
fi

curl -s -X POST \
  -H "Authorization: Bearer ${pat}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/orgs/${org}/actions/runners/registration-token"

