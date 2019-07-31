#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-09-09 23:09:20 +0100 (Sun, 09 Sep 2018)
#
#  https://github.com/harisekhon/devop-perl-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1091
. ./tests/utils.sh

section "Strip ANSI Escape Codes"

name="strip_ansi_escape_codes.pl"

start_time=$(date +%s)

#if is_mac; then
#    cat_opts="-e"
#else
#    cat_opts="-A"
#fi
run++
# $perl defined in utils.sh
# shellcheck disable=SC2154
if echo "some highlighted content" |
    grep --color=yes highlighted |
    $perl -T ./strip_ansi_escape_codes.pl |
    tee /dev/stderr |
    grep -q '^some highlighted content$'; then
    echo "ANSI escape code stripping SUCCEEDED"
 else
    echo "ANSI escape code stripping FAILED"
    exit 1
fi

echo
# $run_count is assigned by run++
# shellcheck disable=SC2154
echo "Total Tests run: $run_count"
time_taken "$start_time" "All version tests for $name completed in"
echo
