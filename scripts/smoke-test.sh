#!/bin/sh
# Copyright (C) 2026  Henrique Almeida
# This file is part of wg-easy rootless.
#
# wg-easy rootless is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# wg-easy rootless is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with wg-easy rootless.  If not, see <https://www.gnu.org/licenses/>.

# Starts an image the way the README runs it and fails unless wg-easy brings up wg0 as 65534.
# Usage: scripts/smoke-test.sh <image>
set -eu

IMAGE="$1"
NAME="wg-easy-rootless-smoke-$$"

cleanup() {
  docker rm -f -v "${NAME}" >/dev/null 2>&1 || :
}
trap cleanup EXIT

fail() {
  echo "smoke test failed: $1" >&2
  docker logs "${NAME}" >&2 || :
  exit 1
}

docker run -d --name "${NAME}" \
  --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_RAW \
  --security-opt no-new-privileges:true --read-only --tmpfs /tmp \
  --sysctl net.ipv4.ip_forward=1 --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --mount type=volume,dst=/etc/wireguard \
  -e INSECURE=true \
  --health-interval 5s --health-start-period 5s \
  "${IMAGE}" >/dev/null

i=0
while :; do
  state="$(docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' "${NAME}")"
  case "${state}" in
  "running healthy") break ;;
  running*) ;;
  *) fail "container is ${state}" ;;
  esac
  i=$((i + 1))
  [ "${i}" -lt 60 ] || fail "not healthy after 120 seconds"
  sleep 2
done

uid="$(docker exec "${NAME}" id -u)"
[ "${uid}" = 65534 ] || fail "running as uid ${uid}"
docker exec "${NAME}" ambient-caps wg show wg0 >/dev/null || fail "wg0 is missing"
echo "smoke test passed: ${IMAGE} healthy as 65534 with wg0 up"
