# wg-easy rootless

[wg-easy](https://github.com/wg-easy/wg-easy) as an unprivileged user that holds only `NET_ADMIN` and `NET_RAW`, on a read-only root filesystem, with no entrypoint or healthcheck override.

The image is the pinned upstream release with three changes. It starts its entrypoint and healthcheck through `ambient-caps`, `wg-quick-non-root.patch` makes `wg-quick` and `awg-quick` skip their `sudo` fallback once they hold `NET_ADMIN`, and it runs as `65534:65534` by default.

## Capabilities for a non-root user

Docker leaves the ambient capability set empty for a non-root user, so a capability granted with `cap_add` is lost at the first `execve`. `node` then starts `wg-quick` with no capabilities, and `wg-quick` answers a non-zero UID by re-executing itself through `sudo`, which the image lacks.

`ambient-caps` is a small static C program installed with `setcap cap_net_admin,cap_net_raw+p`. It raises whichever of `NET_ADMIN` and `NET_RAW` the container grants into the ambient set, skips the one it does not grant, and then runs its arguments. Ambient capabilities survive every `execve` down to `wg`, `ip` and `iptables`.

This was proposed upstream as [wg-easy#2898](https://github.com/wg-easy/wg-easy/pull/2898), which was closed without adding a compiled helper to that codebase.

## Requirements

1. The `wireguard` kernel module is loaded on the host, because the container has no `SYS_MODULE`. Add `wireguard` to `/etc/modules-load.d/wireguard.conf` to load it at boot.
2. The host supports legacy iptables, which the default hooks use. Otherwise, see [Hooks and firewall](#hooks-and-firewall).

## Docker Compose

```yaml
services:
  wg-easy:
    image: h3nc4/wg-easy-rootless:latest
    container_name: wg-easy
    volumes:
      - etc_wireguard:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - NET_RAW
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.default.forwarding=1

volumes:
  etc_wireguard:
```

The image's `/etc/wireguard` belongs to `65534:65534`, and Docker copies that ownership into a new, empty named volume. A fresh install doesn't need a `chown`.

`/tmp` must be writable, since `XTABLES_LOCKFILE` moves the iptables lock there from the read-only `/run`.

## Tags

Each image is named after the upstream release it rebuilds, so `h3nc4/wg-easy-rootless:15.5.0` is wg-easy 15.5.0. The newest release is also tagged `15.5`, `15` and `latest`. Releases from 15.2.0 on are published. The patch fails on older ones, which lack `awg-quick` or change the lines it edits.

Renovate opens a pull request for each new upstream release, and its merge publishes the matching image. A past release is published by running the "Publish Docker Image" workflow by hand with that version, which pushes its exact tag and leaves `latest` alone.

## Moving an existing installation

A volume created by the upstream image belongs to root. Stop the container and hand the volume to the image's user before the first start:

```shell
docker run --rm -v <volume>:/etc/wireguard alpine chown -R 65534:65534 /etc/wireguard
```

A bind mount needs the same `chown` on its directory. To run as another UID, set `user:` and give the volume to that UID instead.

## docker exec

`docker exec` does not start through `ambient-caps`, so a plain `docker exec wg-easy wg show` fails with `Operation not permitted`. Put `ambient-caps` first:

```shell
docker exec wg-easy ambient-caps wg show
```

It has to be the first program of the exec. Behind a shell the permitted set is already empty, and `no-new-privileges` keeps the file capability from refilling it.

## Hooks and firewall

The default PostUp and PostDown hooks and the per-client firewall call `iptables`, which needs `NET_RAW` as well as `NET_ADMIN`. A failing PostUp hook takes the interface down with it.

When the hooks are empty and the per-client firewall is off, such as behind a host firewall, `NET_ADMIN` alone is enough:

1. In the Web UI, empty the PostUp and PostDown hooks under Admin, Hooks, and turn off the per-client firewall under Admin, Interface. Do this first, while the container still holds `NET_RAW`.
2. Remove `NET_RAW` from `cap_add`.

On a host without legacy iptables, write the hooks with `iptables-nft` and `ip6tables-nft`, or with `nft`.

## Running as root

The image still runs as root with `user: "0:0"`, with the same capabilities upstream documents. `ambient-caps` then raises what root already holds.

## Building

```shell
docker build -t h3nc4/wg-easy-rootless .
```

The build fails when an upstream release changes the lines around `auto_su` in `wg-quick` or `awg-quick`, since the patch applies with `--fuzz=0`. A moved line stops the build rather than reaching a VPN that never comes up.

`scripts/smoke-test.sh` starts a built image as `65534` with `NET_ADMIN` and `NET_RAW` on a read-only root and fails unless wg-easy reports healthy with `wg0` up. The workflow runs it before any push:

```shell
./scripts/smoke-test.sh h3nc4/wg-easy-rootless
```

## License

wg-easy rootless is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

wg-easy rootless is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with wg-easy rootless. If not, see <https://www.gnu.org/licenses/>.

The published image contains wg-easy, which is licensed under the GNU Affero General Public License v3.0.
