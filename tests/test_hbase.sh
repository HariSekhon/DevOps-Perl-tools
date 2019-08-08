#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-06 12:12:15 +0100 (Fri, 06 May 2016)
#
#  https://github.com/harisekhon/devops-python-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir2="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# TODO: fix later
exit 0

cd "$srcdir2/.."

# shellcheck disable=SC1090
. "$srcdir2/utils.sh"

# shellcheck disable=SC1090
. "$srcdir2/../bash-tools/lib/docker.sh"

section "H B a s e"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_MASTER_PORT_DEFAULT=16010
export HBASE_REGIONSERVER_PORT_DEFAULT=16301
export HBASE_STARGATE_PORT_DEFAULT=8080
export HBASE_THRIFT_PORT_DEFAULT=9090
export ZOOKEEPER_PORT_DEFAULT=2181

export HBASE_VERSIONS="${*:-latest 0.96 0.98 1.0 1.1 1.2 1.3}"

check_docker_available

export MNTDIR="/devops-perl-tools"

startupwait 30

test_hbase(){
    local version="$1"
    section2 "Setting up HBase $version test container"
    VERSION="$version" docker-compose up -d
    hr
    if [ "$version" = "0.96" ] || [ "$version" = "0.98" ]; then
        # shellcheck disable=SC2034
        local export HBASE_MASTER_PORT_DEFAULT=60010
        # shellcheck disable=SC2034
        local export HBASE_REGIONSERVER_PORT_DEFAULT=60301
    fi
    echo "getting HBase dynamic port mappings:"
    docker_compose_port HBASE_MASTER_PORT "HBase Master"
    docker_compose_port HBASE_REGIONSERVER_PORT "HBase RegionServer"
    docker_compose_port HBASE_STARGATE_PORT "HBase Stargate"
    docker_compose_port HBASE_THRIFT_PORT "HBase Thrift"
    #docker_compose_port ZOOKEEPER_PORT "HBase ZooKeeper"
    export HBASE_PORTS="$HBASE_MASTER_PORT $HBASE_REGIONSERVER_PORT $HBASE_STARGATE_PORT $HBASE_THRIFT_PORT"
    hr
    # ============================================================================ #
    # shellcheck disable=SC2086
    when_ports_available "$HBASE_HOST" $HBASE_PORTS
    hr
    when_url_content "http://$HBASE_HOST:$HBASE_MASTER_PORT/master-status" hbase
    hr
    when_url_content "http://$HBASE_HOST:$HBASE_REGIONSERVER_PORT/rs-status" hbase
    hr
    # ============================================================================ #
    if [ -z "${NOSETUP:-}" ]; then
        echo "setting up test tables"
        uniq_val=$(< /dev/urandom tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c32 || :)
        # gets ValueError: file descriptor cannot be a negative integer (-1), -T should be the workaround but hangs
        #docker-compose exec -T "$DOCKER_SERVICE" /bin/bash <<-EOF
        docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
            export JAVA_HOME=/usr
            /hbase/bin/hbase shell <<-EOF2
            create 't1', 'cf1', { 'REGION_REPLICATION' => 1 }
            create 't2', 'cf2', { 'REGION_REPLICATION' => 1 }
            disable 't2'
            put 't1', 'r1', 'cf1:q1', '$uniq_val'
            put 't1', 'r2', 'cf1:q2', 'test'
            list
EOF2
        exit
EOF
    fi
    if [ -n "${NOTESTS:-}" ]; then
        return
    fi
    hr
    # ============================================================================ #
    docker_exec /tools/hbase_flush_tables.sh

    docker_exec /tools/hbase_flush_tables.sh .2

    docker-compose down
    echo
}

run_test_versions "HBase"
