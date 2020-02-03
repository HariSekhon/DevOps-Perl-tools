#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-28 18:47:41 +0100 (Tue, 28 Jul 2015)
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

cd "$srcdir/..";

# shellcheck disable=SC1091
. ./tests/utils.sh

section "Recase"

# $perl defined by utils
# shellcheck disable=SC2154
if echo oRg.Apache.Hadoop.Mapred.TextInputFormaT | $perl -T ./recase.pl | tee /dev/stderr | grep -q org.apache.hadoop.mapred.TextInputFormat; then
    echo "recasing of Hadoop TextInputFormat succeeded"
 else
    echo "recasing of Hadoop TextInputFormat FAILED"
    exit 1
fi
if echo 'org.apache.hcatalog.pig.hcatloader()' | $perl -T ./recase.pl | tee /dev/stderr | grep -q 'org.apache.hcatalog.pig.HCatLoader()'; then
    echo "recasing of HCatLoader() succeeded"
else
     echo "recasing of HCatLoader() FAILED"
    exit 1
fi
