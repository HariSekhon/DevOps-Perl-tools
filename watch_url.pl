#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2011-05-24 10:38:54 +0100 (Tue, 24 May 2011)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Watch a given URL, outputting status code, content, round trip time and percentages of return codes. Useful for testing web farms and load balancers";

$VERSION = "0.4.6";

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

# This is the max content length if on one line before outputting it on a separate line
my $default_output_length = 40;
my $output_length = $default_output_length;
my $count = 0;
my $interval = 1;
my $output;
my $regex;
my $res;
my $request_timeout = 1;
my $returned = 0;
my $sleep_time;
my $ssl_ca_path;
my $ssl_noverify;
my $status;
my $status_line;
my $time;
my $time_taken;
my $total = 0;
my $tstamp1;
my $tstamp2;
my $url;
my %stats;

$usage_line = "usage: $progname --url http://host.domain.com/page [ --interval=1 --count=0 ]";

%options = (
    "u|url=s"           => [ \$url,           "URL to GET. Will use first arg as URL if this switch is omitted. URL may optionally be prefixed with http:// or https:// for SSL" ],
    "c|count=i"         => [ \$count,         "Number of times to request the given URL. Default: 0 (unlimited)" ],
    "i|interval=f"      => [ \$interval,      "Interval in secs between URL requests. Default: 1" ],
    "t|request-timeout=s" => [ \$request_timeout, "Per request timeout in secs. Default: 1" ],
    "o|output"          => [ \$output,        "Show raw output at end of each line or on new line if output contains carriage returns or newlines or is longer than --output-length characters" ],
    "r|regex=s"         => [ \$regex,         "Output regex match of against entire web page (useful for testing embedded host information of systems behind load balancers)" ],
    "l|output-length=i" => [ \$output_length, "Max length of single line output before putting in on a separate line (defaults to $default_output_length chars)" ],
    "ssl-CA-path=s"     => [ \$ssl_ca_path,   "Path to CA certificate directory to verify SSL certificate if specifying https://" ],
    "ssl-noverify"      => [ \$ssl_noverify,  "Do not verify SSL certificate if specifying https://" ],
);
@usage_order=qw/url count interval request-timeout output regex output-length ssl-CA-path tls-noverify/;

remove_timeout();

get_options();

$url = $ARGV[0] if not defined($url) and defined($ARGV[0]);

#$url =~ /^(http:\/\/\w[\w\.-]+\w(?:\/[\w\.\;\=\&\%\/-]*)?)$/ or die "Invalid URL given\n";
$url = validate_url($url);
#isInt($count)      or usage "Invalid count given, must be a positive integer";
#isFloat($interval) or usage "Invalid sleep interval given, must be a positive floating point number";
#$interval > 0      or usage "Interval must be greater than zero";

#vlog_option "Count", $count ? $count : "$count (unlimited)";
validate_int($count, "count", 0, 1000000);
validate_float($interval, "interval", 0.00001, 1000);
validate_float($request_timeout, "request timeout", 1, 100);
$regex = validate_regex($regex) if $regex;
validate_int($output_length, "output length", 0, 1000);

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon Watch URL version $main::VERSION ");
$ua->show_progress(1) if $debug;
$ua->timeout($request_timeout);

if(defined($ssl_noverify)){
    $ua->ssl_opts( verify_hostname => 0 );
}
if(defined($ssl_ca_path)){
    $ssl_ca_path = validate_directory($ssl_ca_path, "SSL CA directory", undef, "no vlog");
    $ua->ssl_opts( SSL_ca_path => $ssl_ca_path );
}
vlog_option "SSL CA Path",  $ssl_ca_path  if defined($ssl_ca_path);
vlog_option "SSL noverify", $ssl_noverify ? "true" : "false";
vlog2;

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
    $status_line = $res->status_line;
    $status = $res->code;
    $total++;
    if($status !~ /^\d+$/){
        warn "$time\tCODE ERROR: status code '$status' is not a number (status line was: '$status_line')\n";
        next;
    }
    $returned += 1;
    $time_taken = sprintf("%.4f", $tstamp2 - $tstamp1);
    chomp $status_line;
    $msg = "$status_line\t\t$time_taken secs\t\t";
    $stats{$status} += 1;
    $returned = 0;
    foreach(keys %stats){
        $returned += $stats{$_};
    }
    foreach(sort keys %stats){
        #$msg .= "$_ = $stats{$_} (" . int($stats{$_} / $returned * 100) . "% $stats{$_}/$returned) (" . int($stats{$_} / $total * 100) . "% $stats{$_}/$total)\t\t";
        $msg .= "$_ = " . int($stats{$_} / $total * 100) . "% ($stats{$_}/$total),  ";
    }
    $msg =~ s/,\s*$//;
    print "$time\t$i\t\t$msg";
    if($output or $regex or $verbose >= 3){
        my $content = $res->content;
        chomp $content;
        if($regex){
            $content =~ /($regex)/m;
            $content = $1 if $1;
        }
        if(length($content) > $output_length or $content =~ /[\r\n]/){
            print "\ncontent: $content\n";
        } else {
            print "content: $content";
        }
    }
    print "\n";
    if($status_line eq "500 Can't verify SSL peers without knowning which Certificate Authorities to trust"){
        die "\n\n$status_line\n\nPlease specify either --ssl-CA-path or --ssl-noverify\n";
    }
    $sleep_time = ($interval - $time_taken) < 0 ? 0 : ($interval - $time_taken);
    vlog2 "* sleeping for $sleep_time seconds\n";
    sleep $sleep_time;
}
