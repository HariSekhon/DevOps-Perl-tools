#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-28 18:47:41 +0100 (Tue, 28 Jul 2015)
#
#  https://github.com/harisekhon
#
#  License: see accompanying Hari Sekhon LICENSE file
#

set -eu

checksum='75055c31342ba35ea59c4091fff098c7'

pushd `dirname $0` >/dev/null || exit 1

../dockercase.pl Dockerfile > Dockerfile2
if [ "`uname -s`" = 'Darwin' -a "`md5 -q Dockerfile2`"    = "$checksum" ] ||
   [ "`uname -s`" = 'Linux'  -a "`md5sum -q Dockerfile2`" = "$checksum" ]; then
    echo "recasing of Dockerfile succeeded"
 else
    echo "recasing of Dockerfile FAILED"
    exit 1
fi
rm -f Dockerfile2
popd >/dev/null
