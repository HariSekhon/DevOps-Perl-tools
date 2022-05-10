#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-08 14:38:37 +0000 (Thu, 08 Dec 2016)
#
#  https://github.com/HariSekhon/DevOps-Perl-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "$0")" && pwd)"

cd "$srcdir/.."

# shellcheck disable=SC1091
. "bash-tools/lib/docker.sh"

# shellcheck disable=SC1091
. "bash-tools/lib/utils.sh"

section "Docker Image"

export DOCKER_IMAGE="harisekhon/perl-tools"

if is_CI && is_docker_available; then
    [ -n "${NO_DOCKER:-}" ] && exit 0
    [ -n "${NO_PULL:-}" ] ||
        docker pull "$DOCKER_IMAGE"
    docker run --rm -e DEBUG="${DEBUG:-}" -e TRAVIS="${TRAVIS:-}" "$DOCKER_IMAGE" tests/all.sh
fi
