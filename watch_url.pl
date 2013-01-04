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

$VERSION = "0.2";

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
my $sleep_secs = 1;
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
    "u|url=s"               => [ \$url,         "URL to GET in http(s)://host/page.html form" ],
    "s|sleep-interval=f"    => [ \$sleep_secs,  "Sleep interval in seconds between URL requests (default: 1)" ],
    "c|count=i"             => [ \$count,       "Number of times to request the given URL (default: 0 for unlimited)" ],
);
@usage_order=qw/url sleep-interval count/;

delete $options2{"t|timeout=i"};

get_options();

#defined($url) or usage;
#$url =~ /^(http:\/\/\w[\w\.-]+\w(?:\/[\w\.\;\=\&\%\/-]*)?)$/ or die "Invalid URL given\n";
#$url = $1;

$url = validate_url($url);
isInt($count)        or die "Invalid count given, must be a positive integer";
isFloat($sleep_secs) or die "Invalid sleep interval given, must be a positive floating point number";

vlog_options "Count", $count ? $count : "$count (unlimited)";
vlog_options "Sleep Interval", $sleep_secs;
vlog2 "\nSleeping for $sleep_secs seconds between attempts\n\n";

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon Watch URL version $main::VERSION ");
my $req = HTTP::Request->new(GET => $url);

print "="x133 . "\n";
#print "Time\t\t\tCount\t\tResult\t\tHTTP Status Code = Number (% of Total Requests, % of Returned Requests)\n";
print "Timestamp\t\tCount\t\tResult\t\tRound Trip Time\t\tHTTP Status Code = % of Total Requests (number/total)\n";
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
    vlog2 "* sleeping for $sleep_secs seconds";
    sleep $sleep_secs;
}
