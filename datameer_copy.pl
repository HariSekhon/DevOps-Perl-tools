#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-12-06 00:07:05 +0000 (Fri, 06 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Program to copy Datameer configurations from one datameer server to another";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;

my $host2;
my $port2;
my $user2;
my $password2;
my $dir;

%options = (
    %datameer_options,
    "host2=s"         => [ \$host2,         "Datameer server 2 to copy config to" ],
    "port2=s"         => [ \$port2,         "Datameer server 2 port     (default: $DATAMEER_DEFAULT_PORT)" ],
    "user2=s"         => [ \$user2,         "Datameer server 2 user     (defaults to same as datameer server 1)" ],
    "password2=s"     => [ \$password2,     "Datameer server 2 password (defaults to same as datameer server 1)" ],
);
@usage_order = qw/host port user password/;

set_timeout_max(86400);
set_timeout_default(3600);

get_options();

($host, $port, $user, $password)     = validate_host_port_user_password($host, $port, $user, $password);
unless(defined($user2)){
    $user2 = $user;
}
unless(defined($port2)){
    $password2 = $password;
}
($host2, $port2, $user2, $password2) = validate_host_port_user_password($host2, $port2, $user2, $password2);

vlog2;
set_timeout();
set_http_timeout(60);

$status = "OK";

my $url = "http://$host:$port/rest";

foreach(qw/
    connections
    import-job
    workbook
    export-job
    dashboard
    infographics
    /){
    $json = datameer_curl "$url/$_", $user, $password;
    # iterate over ids, fetch, and push to server2
}

quit $status, $msg;
