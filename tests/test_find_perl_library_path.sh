#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-09-27
#
#  https://github.com/harisekhon/devops-perl-tools
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

cd "$srcdir/..";

# shellcheck disable=SC1091
. ./tests/utils.sh

run_grep '/File/Basename.pm$' ./find_perl_library_path.pl File::Basename
run_grep '/JSON.pm' ./find_perl_library_path.pl JSON
run_grep '/JSON.pm' ./find_perl_library_path.pl JSON Time::HiRes
run_grep '/Time/HiRes.pm' ./find_perl_library_path.pl JSON Time::HiRes
run_grep 'lib/HariSekhonUtils.pm' ./find_perl_library_path.pl HariSekhonUtils
run_grep 'lib/HariSekhon/Solr.pm' ./find_perl_library_path.pl HariSekhon::Solr
ERRCODE=2 run_grep '' ./find_perl_library_path.pl nonexistentmodule
ERRCODE=3 run_grep '' ./find_perl_library_path.pl
run_usage ./find_perl_library_path.pl
