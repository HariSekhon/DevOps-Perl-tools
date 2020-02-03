#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-28 18:47:41 +0100 (Tue, 28 Jul 2015)
#
#  https://github.com/harisekhon/devops-perl-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/";

# don't pick up $PATH/spark/bin/utils.sh
# shellcheck disable=SC1091
. ./utils.sh

section "Dockercase"

md5sum="md5sum"
checksum='14afceeaf204606f9027af58a4f70c4c'

# defined by utils
# shellcheck disable=SC2154
$perl -T ../dockercase.pl Dockerfile > Dockerfile2
if [ "$(uname -s)" = 'Darwin' ]; then
    md5sum="md5 -r"
fi
if [ "$($md5sum Dockerfile2 | awk '{print $1}')" = "$checksum" ]; then
    echo "recasing of Dockerfile succeeded"
 else
    echo "recasing of Dockerfile FAILED"
    exit 1
fi
rm -f Dockerfile2
