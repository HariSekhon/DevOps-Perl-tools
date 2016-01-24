#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-28 18:47:41 +0100 (Tue, 28 Jul 2015)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/";

# don't pick up $PATH/spark/bin/utils.sh
. ./utils.sh

md5sum="md5sum"
checksum='14afceeaf204606f9027af58a4f70c4c'

$perl -T $I_lib ../dockercase.pl Dockerfile > Dockerfile2
if [ "`uname -s`" = 'Darwin' ]; then
    md5sum="md5 -r"
fi
if [ "`$md5sum Dockerfile2 | awk '{print $1}'`" = "$checksum" ]; then
    echo "recasing of Dockerfile succeeded"
 else
    echo "recasing of Dockerfile FAILED"
    exit 1
fi
rm -f Dockerfile2
