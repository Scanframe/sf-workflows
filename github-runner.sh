#!/usr/bin/env bash
#
# github-runner.sh - Manage a local Docker container mirroring GitHub Actions runner runtime
#
set -e

# Script directory and repository root
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Include WriteLog function.
source "${script_dir}/inc/logging.inc"
## Trap script exit with function.
trap 'ScriptExit "${BASH_SOURCE}" "${BASH_LINENO}" "${BASH_COMMAND}"' EXIT

# Docker Compose configuration
compose_dir="${script_dir}/docker/github"
compose_file="${compose_dir}/docker-compose.yml"
env_file="${compose_dir}/.env"

# Load environment variables from .env file to get the container name
if [[ -f "${env_file}" ]]; then
	# shellcheck disable=SC1090
	source "${env_file}"
fi

flag_debug=false
flag_dry_run=false

# Container name from environment (set by .env or override)
container_name="${GITHUB_RUNNER_NAME:-github-runner}"

# Docker compose command wrapper
run_docker() {
	local cmd
	cmd=(docker)
	if [[ "${flag_debug}" == "true" ]]; then
		cmd+=(--debug)
	fi
	cmd+=("$@")
	# Run the command.
	"${cmd[@]}"
}

# Docker compose command wrapper
run_compose() {
	local cmd
	cmd=(compose)
	if [[ "${flag_dry_run}" == "true" ]]; then
		cmd+=(--dry-run)
	fi
	cmd+=(--file "${compose_file}" --project-name "github-runner${GITHUB_RUNNER_SUFFIX}" "$@")
	# Run the command.
	run_docker "${cmd[@]}"
}

# Prints help information
show_help() {
	local cmd_name
	cmd_name="$(basename "${0}")"
	cat <<EOF
Usage: ${cmd_name} [<options>] <command> [-- <args...>]
  Manage and run a local Docker container mirroring GitHub Actions workflow job environment.

  Options:
    -h, --help    : Show this help message.
    -d, --dry-run : Dry-run the command(s), not executing them passing '--dry-run' to composer.
    -D, --debug   : Enable verbose logging.
    -s, --suffix  : Suffix for the name of the runner.

  Commands:
    run           : Start the docker compose in the foreground (attached).
    start         : Start the docker compose in the background (detached).
    stop          : Stop and remove the running background container.
    status        : Show the status of composed container.
    log           : Show the log of the composed container.
    exec          : Execute a command or interactive shell inside the container.
                    All arguments after '--' are passed directly to the container.
EOF
}

# Parse options
subcmd=""
exec_args=()

# Parse options.
temp=$(getopt -o 'hdDs:' --long 'help,dry-run,debug,suffix:' -n "$(basename "${0}")" -- "$@")
# shellcheck disable=SC2181
if [[ $? -ne 0 ]]; then
	show_help
	exit 1
fi
eval set -- "$temp"
unset temp
while true; do
	case "${1}" in
		-h | --help)
			show_help
			exit 0
			;;

		-d | --dry-run)
			flag_dry_run=true
			shift
			continue
			;;

		-s | --suffix)
			GITHUB_RUNNER_SUFFIX="${2}"
			export GITHUB_RUNNER_SUFFIX
			# Assign renewed the container appended with the suffix.
			container_name="${GITHUB_RUNNER_NAME}${2}"
			shift 2
			continue
			;;

		-D | --debug)
			flag_debug=true
			shift
			continue
			;;

		'--')
			shift
			break
			;;

		*)
			WriteLog "! Internal error on argument: ${1}" >&2
			exit 1
			;;
	esac
done

# Get the subcommand which is the first positional argument.
subcmd=""
if [[ $# -gt 0 ]]; then
	subcmd="$1"
	shift
fi

# If arguments remain after subcommand
if [[ $# -gt 0 ]]; then
	if [[ "${1}" == "--" ]]; then
		shift
		exec_args+=("${@}")
	else
		exec_args+=("${@}")
	fi
fi

if [[ -z "${subcmd}" ]]; then
	show_help
	exit 0
fi

# Function to check if container is running
is_container_running() {
	local cid
	cid="$(docker ps -q --filter "name=^/${container_name}$")"
	[[ -n "${cid}" ]]
}

# Function to check if container exists (running or stopped)
container_exists() {
	local cid
	cid="$(docker ps -a -q --filter "name=^/${container_name}$")"
	[[ -n "${cid}" ]]
}

# Function to remove container if it exists
remove_container_if_exists() {
	if container_exists; then
		if [[ "${flag_dry_run}" == "true" ]]; then
			WriteLog "# Dry run: would remove container '${container_name}'."
		else
			docker rm -f "${container_name}" >/dev/null 2>&1 || true
		fi
	fi
}

# Command dispatch
case "${subcmd}" in

run)
	if is_container_running; then
		WriteLog "# Container '${container_name}' is already running."
		exit 1
	fi
	remove_container_if_exists
	WriteLog "# Starting GitHub Actions runner container '${container_name}' in foreground."
	run_compose up
	;;

start)
	if is_container_running; then
		WriteLog "# Container '${container_name}' is already running."
	else
		remove_container_if_exists
		WriteLog "# Starting GitHub Actions runner container '${container_name}' in background."
		run_compose up -d
		WriteLog "# Container '${container_name}' started."
	fi
	;;

stop)
	if is_container_running; then
		WriteLog "# Stopping GitHub Actions runner container '${container_name}'."
		run_compose down
		remove_container_if_exists
		WriteLog "# Container '${container_name}' stopped."
	elif container_exists; then
		WriteLog "# Removing stopped container '${container_name}'."
		run_compose down
		remove_container_if_exists
		WriteLog "# Container '${container_name}' removed."
	else
		WriteLog "# Container '${container_name}' is not running."
	fi
	;;

status)
	if is_container_running; then
		WriteLog "# Container '${container_name}' is RUNNING."
		run_compose ps
	elif container_exists; then
		WriteLog "# Container '${container_name}' is STOPPED."
		docker ps -a --filter "name=^/${container_name}$"
	else
		WriteLog "# Container '${container_name}' is NOT created."
	fi
	;;

log)
	if is_container_running; then
		run_compose logs -f "${exec_args[@]}"
	else
		WriteLog "# Container '${container_name}' is not running."
		exit 1
	fi
	;;

exec)
	if is_container_running; then
		if [[ ${#exec_args[@]} -eq 0 ]]; then
			docker exec -it "${container_name}" /bin/bash
		else
			docker exec -it "${container_name}" "${exec_args[@]}"
		fi
	else
		WriteLog "# Container '${container_name}' is not running."
		exit 1
	fi
	;;

*)
	WriteLog "! Error: Unknown command '${subcmd}'"
	WriteLog "Use --help for usage information."
	exit 1
	;;
esac
