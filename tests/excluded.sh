#!/usr/bin/env bash
# shellcheck disable=SC2230
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
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

# intended only to be sourced by utils.sh
#
# split from utils.sh as this is specific to this repo

set -eu
[ -n "${DEBUG:-}" ] && set -x

${perl:-perl} -e 'use Net::ZooKeeper' &>/dev/null && zookeeper_built="true" || zookeeper_built=""

isExcluded(){
    local prog="$1"
    [[ "$prog" =~ ^\* ]] && return 0
    [[ "$prog" =~ Makefile.PL ]] && return 0
    # ignore zookeeper plugins if Net::ZooKeeper module is not available
    if grep -q "Net::ZooKeeper" "$prog" && ! [ $zookeeper_built ]; then
        echo "skipping $prog due to Net::ZooKeeper dependency not having been built (do 'make zookeeper' if intending to use this plugin)"
        return 0
    fi
    # this external git check is expensive, skip it when in CI as using fresh git checkouts
    is_CI && return 1
    if type -P git &>/dev/null; then
        commit="$(git log "$prog" | head -n1 | grep 'commit')"
        if [ -z "$commit" ]; then
            return 0
        fi
    fi
    return 1
}
