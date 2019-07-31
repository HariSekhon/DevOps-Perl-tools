#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-29 15:05:43 +0100 (Wed, 29 Jul 2015)
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

cd "$srcdir/.."

# shellcheck disable=SC1091
. ./tests/utils.sh

section "DrillCase"

name=drillcase

start_time=$(date +%s)

run++
# $perl defined in utils
# shellcheck disable=SC2154
if echo "select columns[0] from myTable where name = 'hari';" | $perl -T ./drillcase.pl | tee /dev/stderr | grep -qF "SELECT columns[0] FROM myTable WHERE name = 'hari';"; then
    echo "recasing of Drill statement succeeded"
else
    echo "recasing of Drill statement FAILED"
    exit 1
fi

echo
# $run_count defined in run++
# shellcheck disable=SC2154
echo "Total Tests run: $run_count"
time_taken "$start_time" "All version tests for $name completed in"
echo
