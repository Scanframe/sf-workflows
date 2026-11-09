#!/usr/bin/env bash

# Get the script directory.
script_dir="$(cd "$(dirname "${0}")" && pwd)"
# Include WriteLog function.
source "${script_dir}/inc/logging.inc"
## Trap script exit with function.
trap 'ScriptExit "${BASH_SOURCE}" "${BASH_LINENO}" "${BASH_COMMAND}"' EXIT

# Prints the help.
#
function show_help {
	local cmd_name
	# Get only the filename of the current script.
	cmd_name="$(basename "${0}")"
	echo "Usage: ${cmd_name} [<options>] [register | daemon | run | daemon| status | stop | kill]
  Execute a single or multiple actions for docker and/or it's container.

  Options:
    -h, --help  : Show this help.
    -t, --token : GitLab runner registration token.
    --terminal  : Runs the script in a terminal xterm.
    --pause     : Wait

  Commands/Steps:
    General:
      register: Register the GitLab runner (use token option).
      run     : Run the runner interactively with debug log-level.
      start   : Run the runner in the background.
      list    : GitLab-runner list command.
      status  : GitLab-runner status command.
      attach  : Attach to a console of the Docker container.
      stop    : Stops a background running runner.
      kill    : Kills a background running runner.
"
}

# When no arguments or options are given show the help.
if [[ $# -eq 0 || $# -eq 1 && "$1" == "--" ]]; then
	show_help
	exit 1
fi

# Set container name to be used.
container_name="gitlab-runner"
# Set the image name to be used.
img_name="gitlab/gitlab-runner:latest"
# Location of the configuration directory.
config_dir="$(realpath "${script_dir}")/docker/gitlab/config"
# GitLab URL.
url_gitlab="https://git.scanframe.com"
# Registration token.
reg_token="<my token>"
# Hostname of the docker running gitlab-runner.
container_name="gitlab-runner"

# Change to the current script directory.
cd "${script_dir}" || exit 1

# Store the first argument for comparison.
first_arg="$1"
pause_flag=false

# Parse options.
temp=$(getopt -o 'ht:' --long 'help,token:,terminal,pause' -n "$(basename "${0}")" -- "$@")
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

		--pause)
			pause_flag=true
			shift
			;;

		--terminal)
			if [[ "${1}" != "${first_arg}" ]]; then
				WriteLog "! Option '${1}' must be the first argument."
				exit 1
			fi
			shift
			set -x
			xterm -T "GitLab Runner" -geometry 120x25 +ai -bg black -fg white -sl 3000 -fs 10 -fa 'Noto Mono' -e "$0" "$@"
			exit 0
			;;

		-t | --token)
			reg_token="${2}"
			shift 2
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

# Get the subcommand.
cmd=""
if [[ $# -gt 0 ]]; then
	cmd="$1"
	shift
fi

case "${cmd}" in

	register)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			WriteLog "Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		#	--device /dev/fuse --privileged
		docker run \
			--name "${container_name}" --rm --tty --interactive \
			--user "0:$(id -g)" \
			--cap-add SYS_ADMIN --security-opt apparmor:unconfined \
			--volume "${config_dir}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${container_name}" \
			"${img_name}" register \
			--url "${url_gitlab}" \
			--token "${reg_token}" \
			--executor "docker"
		;;

	run)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			WriteLog "# Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		# --restart always
		# --env DATA_DIR="/tmp/config" \
		docker --debug run --rm \
			--name "${container_name}" \
			--user "0:$(id -g)" \
			--volume "${config_dir}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${container_name}" \
			"${img_name}" --log-level debug run
		;;

	start)
		# Stop all containers using this image.
		# shellcheck disable=SC2046
		if [[ -n "$(docker ps -a -q --filter ancestor="${img_name}")" ]]; then
			WriteLog "# Stopping containers using image '${img_name}'."
			docker stop $(docker ps -a -q --filter ancestor="${img_name}")
		fi
		# --restart always
		# --env DATA_DIR="/tmp/config" \
		docker --debug run --rm --detach \
			--name "${container_name}" \
			--user "0:$(id -g)" \
			--volume "${config_dir}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${container_name}" \
			"${img_name}" start
		;;

	attach)
		# Connect to the last started container using new bash shell.
		docker start "${container_name}"
		docker exec --interactive --tty "${container_name}" /bin/bash
		;;

	stop | kill)
		# Stop this docker container only.
		cntr_id="$(docker ps --filter name="${container_name}" --quiet)"
		if [[ -n "${cntr_id}" ]]; then
			WriteLog "Container ID is '${cntr_id}' and performing '${cmd}' command."
			docker "${cmd}" "${cntr_id}"
		else
			WriteLog "Container '${container_name}' is not running."
		fi
		;;

	status | list | help)
		docker run --rm --tty --interactive \
			--name "${container_name}" \
			--user "0:$(id -g)" \
			--volume "${config_dir}:/etc/gitlab-runner:rw" \
			--volume "/var/run/docker.sock:/var/run/docker.sock:rw" \
			--hostname "${container_name}" \
			"${img_name}" "${cmd}"
		;;

	*)
		WriteLog "Command '${cmd}' is invalid!"
		show_help
		exit 1
		;;

esac

if ${pause_flag}; then
	read -n1 -r -p 'Press any key to continue...'
fi
