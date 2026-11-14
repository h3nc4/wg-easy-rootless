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

################################################################################
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS ambient-caps

RUN apk add --no-cache build-base linux-headers

WORKDIR /src
COPY ambient-caps.c ./
RUN cc -O2 -Wall -Wextra -Werror -static -s -o /ambient-caps ambient-caps.c

################################################################################
FROM codeberg.org/wg-easy/wg-easy:15@sha256:071f79a639e9361123a5e57733107320207b844ddbbd92dfa6962f541fe8aac8 AS final

COPY --from=ambient-caps /ambient-caps /usr/local/bin/ambient-caps

COPY wg-quick-non-root.patch /tmp/

# --fuzz=0 fails the build when an upgrade moves the lines around auto_su in either script.
RUN apk add --no-cache libcap-setcap patch \
  && patch --directory=/ --strip=1 --fuzz=0 --input=/tmp/wg-quick-non-root.patch \
  && rm /tmp/wg-quick-non-root.patch \
  && setcap cap_net_admin,cap_net_raw+p /usr/local/bin/ambient-caps \
  && chown 65534:65534 /etc/wireguard \
  && apk del --no-cache libcap-setcap patch

ENV XTABLES_LOCKFILE=/tmp/xtables.lock

USER 65534:65534

HEALTHCHECK --interval=1m --timeout=5s --retries=3 CMD ["/usr/local/bin/ambient-caps", "/usr/bin/timeout", "5s", "/bin/sh", "-c", "/usr/bin/wg show | /bin/grep -q interface"]

ENTRYPOINT ["/usr/local/bin/ambient-caps", "docker-entrypoint.sh"]
CMD ["/usr/bin/dumb-init", "node", "server/index.mjs"]

LABEL org.opencontainers.image.title="wg-easy rootless" \
  org.opencontainers.image.description="wg-easy as an unprivileged user holding only NET_ADMIN and NET_RAW" \
  org.opencontainers.image.authors="Henrique Almeida <me@h3nc4.com>" \
  org.opencontainers.image.vendor="Henrique Almeida" \
  org.opencontainers.image.licenses="GPL-3.0-or-later AND AGPL-3.0-only" \
  org.opencontainers.image.source="https://github.com/h3nc4/wg-easy-rootless"
