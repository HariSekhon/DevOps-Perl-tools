#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2011-05-24 10:38:54 +0100 (Tue, 24 May 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# Utility to watch a given URL and output it's status code. Useful for testing web farms and load balancers

$VERSION = "0.2.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;
use POSIX;
use Time::HiRes qw/sleep time/;

my $count = 0;
my $res;
my $returned = 0;
my $interval = 1;
my $status;
my $status_line;
my $time;
my $total = 0;
my $url;
my %stats;
my $time_taken;
my $tstamp1;
my $tstamp2;

$usage_line = "usage: $progname --url 'http://host/blah' --sleep-interval=1 --count=0 (unlimited)";

%options = (
    "u|url=s"         => [ \$url,         "URL to GET in http(s)://host/page.html form" ],
    "c|count=i"       => [ \$count,       "Number of times to request the given URL. Default: 0 (unlimited)" ],
    "i|interval=f"    => [ \$interval,  "Interval in secs between URL requests. Default: 1" ],
);
@usage_order=qw/url count interval/;

delete $HariSekhonUtils::default_options{"t|timeout=i"};

get_options();

#$url =~ /^(http:\/\/\w[\w\.-]+\w(?:\/[\w\.\;\=\&\%\/-]*)?)$/ or die "Invalid URL given\n";
$url = validate_url($url);
isInt($count)      or usage "Invalid count given, must be a positive integer";
isFloat($interval) or usage "Invalid sleep interval given, must be a positive floating point number";
$interval > 0      or usage "Interval must be greater than zero";

vlog_options "Count", $count ? $count : "$count (unlimited)";
vlog_options "Sleep interval", $interval;

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon Watch URL version $main::VERSION ");
my $req = HTTP::Request->new(GET => $url);

print "="x133 . "\n";
#print "Time\t\t\tCount\t\tResult\t\tHTTP Status Code = Number (% of Total Requests, % of Returned Requests)\n";
print "Time\t\t\tCount\t\tResult\t\tRound Trip Time\t\tHTTP Status Code = % of Total Requests (number/total)\n";
print "="x133 . "\n";
#while(1){
for(my $i=1;$i<=$count or $count eq 0;$i++){
    $time = strftime("%F %T", localtime);
    vlog2 "* sending request";
    $tstamp1 = time;
    $res     = $ua->request($req);
    $tstamp2 = time;
    vlog2 "* got response";
    $status  = $status_line  = $res->status_line;
    $status  =~ s/\s.*$//;
    $total++;
    if($status !~ /^\d+$/){
        print "$time\tCODE ERROR: status code '$status' is not a number (status line was: '$status_line')\n";
        next;
    }
    $returned += 1;
    $time_taken = sprintf("%.4f", $tstamp2 - $tstamp1);
    $msg = "$status_line\t\t$time_taken secs\t\t";
    $stats{$status} += 1;
    $returned = 0;
    foreach(keys %stats){
        $returned += $stats{$_};
    }
    foreach(sort keys %stats){
        #$msg .= "$_ = $stats{$_} (" . int($stats{$_} / $returned * 100) . "% $stats{$_}/$returned) (" . int($stats{$_} / $total * 100) . "% $stats{$_}/$total)\t\t";
        $msg .= "$_ = " . int($stats{$_} / $total * 100) . "% ($stats{$_}/$total)\t\t";
    }
    print "$time\t$i\t\t$msg\n";
    vlog2 "* sleeping for $interval seconds";
    sleep $interval;
}
