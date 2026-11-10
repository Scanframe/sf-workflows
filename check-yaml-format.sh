#!/usr/bin/env bash

set -e

# Check that yamllint is installed
if ! command -v yamllint &>/dev/null; then
  echo "Error: yamllint is not installed or not in PATH." >&2
  exit 1
fi

# Script directory and repository root
script_dir="$(cd "$(dirname "${0}")" && pwd)"

# Lint all YAML files in the project using the .yamllint config
# The -c flag points to the config file, -f parsable gives CI-friendly output
# Passing the script directory lints all YAML files recursively
yamllint -c "${script_dir}/.yamllint.yml" -f parsable "${script_dir}"