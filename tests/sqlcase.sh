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

pushd `dirname $0` >/dev/null || exit 1

if echo "select * from blah" | ../sqlcase.pl | tee /dev/stderr | grep -q 'SELECT \* FROM blah'; then
    echo "recasing of SQL succeeded"
 else
    echo "recasing of SQL FAILED"
    exit 1
fi
popd >/dev/null
