#!/usr/bin/perl -T
#
#   Author: Hari Sekhon
#   Date: 2011-05-24 10:38:54 +0100 (Tue, 24 May 2011)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4:et

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/../lib";
}
use HariSekhonUtils;
use LWP::UserAgent;
use POSIX;
use Time::HiRes qw/sleep time/;

my $accepted;
my $active;
my $conns_sec;
my $content;
my $count = 0;
my $handled;
my $last_accepted = 0;
my $last_requests = 0;
my $last_time;
my $now;
my $reading;
my $requests;
my $requests_sec;
my $res;
my $interval = 1;
my $status;
my $status_line;
my $time;
my $time_diff;
my $url;
my $waiting;
my $writing;

$usage_line = "usage: $progname -u 'http://host/nginx_status' --interval=1 --count=0 (unlimited)\n";

%options = (
    "u|url=s"       => [ \$url,         "URL to the Nginx status/stats page from which to collect nginx stats" ],
    "c|count=i"     => [ \$count,       "Number of times to collect stats. Default: 0 (unlimited)" ],
    "i|interval=f"  => [ \$interval,    "Interval in secs between stats requests. Default: 1" ],
);
@usage_order = qw/url count interval/;

delete $HariSekhonUtils::default_options{"t|timeout=i"};

get_options();

#$url =~ /^(http:\/\/\w[\w\.-]+\w\/[\w\.\;\=\&\%\/-]+)$/ or die "Invalid URL given\n";
$url = validate_url($url, "Nginx Stats");
isInt($count)      or usage "Invalid number of attempts given";
isFloat($interval) or usage "Invalid sleep interval given, must be a float";
$interval > 0      or usage "Interval must be greater than zero";

vlog_options "Count", $count ? $count : "$count (unlimited)";
vlog_options "Sleep interval", $interval;

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon Watch Nginx Stats version $main::VERSION");
my $req = HTTP::Request->new(GET => $url);

print "\t"x12 . "=============== Totals =================\n";
print "Time\t\t\tCount\t\tActive\tReading\tWriting\tWaiting\tConn/s\tRequests/s\tAccepted\tHandled\t\tRequests\n";
for(my $i=1;$i<=$count or $count eq 0;$i++){
    $now  = time;
    $time = strftime("%F %T", localtime);
    vlog3 "sending request";
    $res     = $ua->request($req);
    vlog3 "got response";
    $status  = $status_line  = $res->status_line;
    $status  =~ s/\s.*$//;
    if(! isInt($status)){
        print "$time\tCODE ERROR: status code '$status' is not a number (status line was: '$status_line')\n";
        next;
    }
    vlog3 "status line: $status_line";
    unless($status eq 200){
        warn "$time\tWARNING: '$status_line'\n";
        sleep $interval;
        next;
    }
    $content = $res->content;
    if($content =~ /^\s*$/){
        warn "$time\tWARNING: no content received from '$url'\n";
        sleep $interval;
        next;
    }
    unless($content =~ /Active connections:\s+(\d+)/){
        warn "$time\tWARNING: Cannot find Active connections in output\n";
        warn "content: '$content'\n";
        sleep $interval;
        next;
    }
    $active = $1;
    unless($content =~ /server accepts handled requests\n\s+(\d+)\s+(\d+)\s+(\d+)/){
        warn "$time\tWARNING: Cannot find 'server accepts handled requests' in output\n";
        warn "content: '$content'\n";
        sleep $interval;
        next;
    }
    $accepted = $1;
    $handled  = $2;
    $requests = $3;
    #if($requests > $handled or $handled > $accepted){
    #    warn "WARNING: requests > handled or handled > accepted, something is WRONG!\n";
    if($handled > $accepted){
        warn "WARNING: handled > accepted, something is WRONG!\n";
        #sleep $interval;
        #next;
    }
    unless($content =~ /Reading:\s+(\d+)\s+Writing:\s+(\d+)\s+Waiting:\s+(\d+)/){
        warn "\tWARNING: Cannot find 'Reading/Writing/Waiting' in output\n";
        warn "content: '$content'\n";
        sleep $interval;
        next;
    }
    $reading = $1;
    $writing = $2;
    $waiting = $3;
    if($i eq 1){
        $conns_sec = $requests_sec = "N/A";
    } else {
        $time_diff = $now - $last_time;
        if($time_diff < 1){
            $conns_sec = $requests_sec = "N/A";
        } else {
            $conns_sec    = int( ($accepted - $last_accepted) / $time_diff );
            $requests_sec = int( ($requests - $last_requests) / $time_diff );
        }
    }
    $last_time = $now;
    $last_accepted = $accepted;
    $last_requests = $requests;
    print "$time\t$i\t\t$active\t$reading\t$writing\t$waiting\t$conns_sec\t$requests_sec\t\t$accepted\t\t$handled\t\t$requests\n";
    vlog3 "sleeping for $interval seconds";
    sleep $interval;
}
exit 0;
