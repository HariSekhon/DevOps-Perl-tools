#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 23:53:45 +0000 (Thu, 05 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Program to revision control Datameer configuration.

Inspired by Rancid and the Datameer checks from the Advanced Nagios Plugins Collection";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;

my $dir;

%options = (
    %datameer_options,
    "git-dir=s",    [ \$dir,    "Directory git repo lives in" ],
);
@usage_order = qw/host port user password git-dir/;

set_timeout_max(3600);
set_timeout_default(600);

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$dir = validate_directory($dir, "git");

vlog2;
set_timeout();
set_http_timeout(30);

$status = "OK";

chdir($dir) or die "failed to chdir to git directory $dir\n";
# test isGit and also check for safety placeholder to make sure we're in the right repo

my $url = "http://$host:$port/rest/";

foreach(qw/
    connections
    import-job
    workbook
    export-job
    dashboard
    infographics
    /){
    $json = datameer_curl "$url/$_", $user, $password;
    # iterate over ids, fetch and save to file hierarchy under git
}

# git diff and git commit

quit $status, $msg;
