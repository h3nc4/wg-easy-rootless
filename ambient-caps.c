// Copyright (C) 2026  Henrique Almeida
// This file is part of wg-easy rootless.
//
// wg-easy rootless is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// wg-easy rootless is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with wg-easy rootless.  If not, see <https://www.gnu.org/licenses/>.

// Raises NET_ADMIN and NET_RAW into the ambient set when the process holds them, then runs its arguments.
// Ambient capabilities survive exec as a non-root user, and a capability the container does not grant is skipped.

#include <linux/capability.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

static const int caps[] = {CAP_NET_ADMIN, CAP_NET_RAW};
#define NCAPS (sizeof caps / sizeof caps[0])

int main(int argc, char *argv[]) {
  struct __user_cap_header_struct header = {_LINUX_CAPABILITY_VERSION_3, 0};
  struct __user_cap_data_struct data[_LINUX_CAPABILITY_U32S_3];

  if (argc < 2) {
    fprintf(stderr, "usage: %s program [argument ...]\n", argv[0]);
    return 2;
  }

  if (syscall(SYS_capget, &header, data) == 0) {
    for (size_t i = 0; i < NCAPS; i++) {
      if (data[0].permitted & (1U << caps[i])) {
        data[0].inheritable |= 1U << caps[i];
      }
    }
    if (syscall(SYS_capset, &header, data) == 0) {
      for (size_t i = 0; i < NCAPS; i++) {
        if (data[0].inheritable & (1U << caps[i])) {
          prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, caps[i], 0, 0);
        }
      }
    }
  }

  execvp(argv[1], argv + 1);
  perror(argv[1]);
  return 127;
}
