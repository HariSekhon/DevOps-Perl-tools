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
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. tests/travis.sh

if echo oRg.Apache.Hadoop.Mapred.TextInputFormaT | $perl -T $I_lib ./recase.pl | tee /dev/stderr | grep -q org.apache.hadoop.mapred.TextInputFormat; then
    echo "recasing of Hadoop TextInputFormat succeeded"
 else
    echo "recasing of Hadoop TextInputFormat FAILED"
    exit 1
fi
if echo 'org.apache.hcatalog.pig.hcatloader()' | $perl -T $I_lib ./recase.pl | tee /dev/stderr | grep -q 'org.apache.hcatalog.pig.HCatLoader()'; then
    echo "recasing of HCatLoader() succeeded"
else
     echo "recasing of HCatLoader() FAILED"
    exit 1
fi
