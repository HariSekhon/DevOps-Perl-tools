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

cd "$srcdir/..";

. ./tests/utils.sh

if echo "select * from blah" | $perl -T $I_lib ./sqlcase.pl | tee /dev/stderr | grep -q 'SELECT \* FROM blah'; then
    echo "recasing of SQL succeeded"
 else
    echo "recasing of SQL FAILED"
    exit 1
fi
