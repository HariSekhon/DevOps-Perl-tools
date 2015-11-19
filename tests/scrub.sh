#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-07-28 18:47:41 +0100 (Tue, 28 Jul 2015)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#

set -eu
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. tests/travis.sh

src[0]="2015-11-19 09:59:59,893 - Execution of 'mysql -u root --password=somep@ssword! -h myHost.internal  -s -e \"select version();\"' returned 1. ERROR 2003 (HY000): Can't connect to MySQL server on 'host.domain.com' (111)"
dest[0]="2015-11-19 09:59:59,893 - Execution of 'mysql -u root --password=<password> -h <fqdn>  -s -e \"select version();\"' returned 1. ERROR 2003 (HY000): Can't connect to MySQL server on '<fqdn>' (111)"

src[1]="2015-11-19 09:59:59 - Execution of 'mysql -u root --password=somep@ssword! -h myHost.internal  -s -e \"select version();\"' returned 1. ERROR 2003 (HY000): Can't connect to MySQL server on 'host.domain.com' (111)"
dest[1]="2015-11-19 09:59:59 - Execution of 'mysql -u root --password=<password> -h <fqdn>  -s -e \"select version();\"' returned 1. ERROR 2003 (HY000): Can't connect to MySQL server on '<fqdn>' (111)"

src[2]='File "/var/lib/ambari-agent/cache/common-services/RANGER/0.4.0/package/scripts/ranger_admin.py", line 124, in <module>'
dest[2]='File "/var/lib/ambari-agent/cache/common-services/RANGER/0.4.0/package/scripts/ranger_admin.py", line 124, in <module>'

src[3]='File "/usr/lib/python2.6/site-packages/resource_management/libraries/script/script.py", line 218, in execute'
dest[3]='File "/usr/lib/python2.6/site-packages/resource_management/libraries/script/script.py", line 218, in execute'

src[4]='resource_management.core.exceptions.Fail: Ranger Database connection check failed'
dest[4]='resource_management.core.exceptions.Fail: Ranger Database connection check failed'

src[5]='21 Sep 2015 02:28:45,580  INFO [qtp-ambari-agent-6292] HeartBeatHandler:657 - State of service component MYSQL_SERVER of service HIVE of cluster ...'
dest[5]='21 Sep 2015 02:28:45,580  INFO [qtp-ambari-agent-6292] HeartBeatHandler:657 - State of service component MYSQL_SERVER of service HIVE of cluster ...'

src[6]='21 Sep 2015 14:54:44,811  WARN [ambari-action-scheduler] ActionScheduler:311 - Operation completely failed, aborting request id:113'
dest[6]='21 Sep 2015 14:54:44,811  WARN [ambari-action-scheduler] ActionScheduler:311 - Operation completely failed, aborting request id:113'

for (( i = 0 ; i < ${#src[@]} ; i++ )); do
    result="$($perl -T $I_lib ./scrub.pl -a <<< "$src[$i]")"
    if ! grep -Fq "$dest[$i]" <<< "$result"; then
        echo "FAILED to scrub line"
        echo "input:    $src[$i]"
        echo "expected: $dest[$i]"
        echo "got:      $result"
        exit 1
    fi
    echo "SUCCEEDED scrubbing test $i"
done
