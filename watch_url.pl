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

# TODO: reintegrate with HariSekhonUtils

$main::VERSION = "0.1";

use strict;
use warnings;
use File::Basename;
use Getopt::Long qw(:config bundling);
use LWP::UserAgent;
use POSIX;
use Time::HiRes qw/sleep time/;

my $help;
my $host;
my $msg;
my $count = 0;
my $port;
my $res;
my $returned = 0;
my $sleep_secs = 1;
my $status;
my $status_line;
my $time;
my $total = 0;
my $url;
my $verbose = 0;
my $version;
my %stats;
my $time_taken;
my $tstamp1;
my $tstamp2;

my $progname = basename $0; 

sub usage{
    die "usage: $progname -u 'http://host/blah' --sleep-interval=1 --count=0 (unlimited)\n";
}

sub vlog{
    print "@_\n" if $verbose;
}

GetOptions (
            "h|help|usage"          => \$help,
            "c|count=i"             => \$count,
            "s|sleep-interval=s"    => \$sleep_secs,
            "u|url=s"               => \$url,
            "v|verbose+"            => \$verbose,
            "V|version"             => \$version,
           ) or usage;

usage if defined($help);
die "Version $main::VERSION\n" if defined($version);

$count =~ /^(\d+)$/ or die "Invalid count given\n";
$count = $1;

$sleep_secs =~ /^(\d+(?:\.\d+)?)$/ or die "Invalid sleep interval given\n";
$sleep_secs = $1;

defined($url) or usage;
$url =~ /^(http:\/\/\w[\w\.-]+\w(?:\/[\w\.\;\=\&\%\/-]*)?)$/ or die "Invalid URL given\n";
$url = $1;
print "Watch URL: $url\n";
print "Count: ";
print "$count";
print " (unlimited)" if ($count eq 0);
print "\n";
print "Sleeping for $sleep_secs seconds between attempts\n\n";

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon Watch URL version $main::VERSION ");
my $req = HTTP::Request->new(GET => $url);

#print "Time\t\t\tCount\t\tResult\t\tHTTP Status Code = Number (% of Total Requests, % of Returned Requests)\n";
print "Timestamp\t\tCount\t\tResult\t\tRound Trip Time\t\tHTTP Status Code = % of Total Requests (number/total)\n";
#while(1){
for(my $i=1;$i<=$count or $count eq 0;$i++){
    $time = strftime("%F %T", localtime);
    vlog "sending request";
    $tstamp1 = time;
    $res     = $ua->request($req);
    $tstamp2 = time;
    vlog "got response";
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
    vlog "sleeping for $sleep_secs seconds";
    sleep $sleep_secs;
}
