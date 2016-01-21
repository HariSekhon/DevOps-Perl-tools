#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-21 14:52:03 +0000 (Thu, 21 Jan 2016)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#

set -eu
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

if echo "create keyspace hari with replication = {'class':'simplestrategy','replication_factor':3};" | $perl -T $I_lib ./cqlcase.pl | tee /dev/stderr | grep -q "CREATE KEYSPACE hari WITH replication = {'class':'SimpleStrategy','replication_factor':3};"; then
    echo "recasing of CQL succeeded"
 else
    echo "recasing of CQL FAILED"
    exit 1
fi
