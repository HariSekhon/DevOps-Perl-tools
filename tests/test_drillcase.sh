#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-29 15:05:43 +0100 (Wed, 29 Jul 2015)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd $srcdir/..

. ./tests/utils.sh

if echo "select columns[0] from myTable where name = 'hari';" | $perl -T $I_lib drillcase.pl | tee /dev/stderr | grep -qF "SELECT columns[0] FROM myTable WHERE name = 'hari';"; then
    echo "recasing of Drill statement succeeded"
else
    echo "recasing of Drill statement FAILED"
    exit 1
fi
