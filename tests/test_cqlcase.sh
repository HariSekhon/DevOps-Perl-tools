#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-21 14:52:03 +0000 (Thu, 21 Jan 2016)
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
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1091
. ./tests/utils.sh

section "CQLCase"

name=cqlcase

start_time=$(date +%s)

run++
# $perl defined in utils
# shellcheck disable=SC2154
if echo "create keyspace hari with replication = {'class':'simplestrategy','replication_factor':3};" | $perl -T ./cqlcase.pl | tee /dev/stderr | grep -q "CREATE KEYSPACE hari WITH replication = {'class':'SimpleStrategy','replication_factor':3};"; then
    echo "recasing of CQL succeeded"
 else
    echo "recasing of CQL FAILED"
    exit 1
fi

echo
# $run count defined in run++
# shellcheck disable=SC2154
echo "Total Tests run: $run_count"
time_taken "$start_time" "All version tests for $name completed in"
echo
