#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# intended only to be sourced by utils.sh
#
# split from utils.sh as this is specific to this repo

set -eu
[ -n "${DEBUG:-}" ] && set -x

$perl -e 'use Net::ZooKeeper' &>/dev/null && zookeeper_built="true" || zookeeper_built=""

isExcluded(){
    local prog="$1" 
    [[ "$prog" =~ ^\* ]] && return 0
    # ignore zookeeper plugins if Net::ZooKeeper module is not available
    if grep -q "Net::ZooKeeper" "$prog" && ! [ $zookeeper_built ]; then
        echo "skipping $prog due to Net::ZooKeeper dependency not having been built (do 'make zookeeper' if intending to use this plugin)"
        return 0
    fi
    commit="$(git log "$prog" | head -n1 | grep 'commit')"
    if [ -z "$commit" ]; then
        return 0
    fi
    return 1
}
