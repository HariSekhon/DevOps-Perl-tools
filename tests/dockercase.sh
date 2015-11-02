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

md5sum="md5sum"
checksum='14afceeaf204606f9027af58a4f70c4c'

pushd `dirname $0` >/dev/null || exit 1

../dockercase.pl Dockerfile > Dockerfile2
if [ "`uname -s`" = 'Darwin' ]; then
    md5sum="md5"
fi
if [ "`$md5sum Dockerfile2 | awk '{print $2}'`" = "$checksum" ]; then
    echo "recasing of Dockerfile succeeded"
 else
    echo "recasing of Dockerfile FAILED"
    md5 Dockerfile2
    exit 1
fi
rm -f Dockerfile2
popd >/dev/null
