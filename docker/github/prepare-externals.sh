#!/usr/bin/env bash
# Copies the runner externals (node20/node24) from the runner image to the HOST at the same path the
# runner uses internally, because container jobs get it mounted as /__e by the host Docker daemon.
set -euo pipefail

cd "$(dirname "$0")"

image="myoung34/github-runner:latest"
target="/actions-runner/externals"

sudo rm -rf /tmp/runner/work

docker pull "${image}"
id="$(docker create "${image}")"
trap 'docker rm "${id}" >/dev/null' EXIT

sudo mkdir -p "$(dirname "${target}")"
sudo rm -rf "${target}"
sudo docker cp "${id}":/actions-runner/externals "${target}"
ls "${target}"

docker compose up --force-recreate
#docker compose up -d --force-recreate
