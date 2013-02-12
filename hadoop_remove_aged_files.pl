#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-01-14 20:50:13 +0000 (Mon, 14 Jan 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Deletes files from Hadoop's HDFS /tmp directory that are older than X days

Credit to my old colleague Rob Dawson @ Specific Media for giving me this idea during lunch";

$VERSION = "0.1";

use strict;
use warnings;
use Time::Local;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

$ENV{"PATH"} .= ":/opt/hadoop/bin:/usr/local/hadoop/bin";

my $default_hadoop_bin = "hadoop";
my $hadoop_bin = $default_hadoop_bin;

my $DEFAULT_PATH = "/tmp";
my $path = $DEFAULT_PATH;

my $days;
my $exclude;
my $expunge = 0;

set_timeout_max(86400);    # 1 day max -t timeout
set_timeout_default(1800); # 30 mins. hadoop fs -lsr /tmp took 6 minutes to list 1720943 files/dirs on my test cluster!

my %months = (
    "Jan" => 0,
    "Feb" => 1,
    "Mar" => 2,
    "Apr" => 3,
    "May" => 4,
    "Jun" => 5,
    "Jul" => 6,
    "Aug" => 7,
    "Sep" => 8,
    "Oct" => 9,
    "Nov" => 10,
    "Dec" => 11
);

%options = (
    "d|days=f"      =>  [ \$days,       "Number of days after which to delete files, can be a float" ],
    "p|path=s"      =>  [ \$path,       "Path for which to remove old files (default: $DEFAULT_PATH)" ],
    "e|exclude=s"   =>  [ \$exclude,    "Regex of files to exclude from being deleted" ],
    "expunge"       =>  [ \$expunge,    "Call expunge after deletion. By default things are deleted to trash so they don't actually reclaim the space without this switch" ],
    "hadoop-bin=s"  =>  [ \$hadoop_bin, "Path to 'hadoop' command if not in \$PATH" ],
);
@usage_order = qw/days path exclude expunge hadoop-bin/;
get_options();

my $echo = "";
$echo = "echo" if $debug;

$days    = validate_float($days, 0.003, 3650, "days");
$path    = validate_filename($path); # because validate_dir[ectory] checks the directory existance on the local filesystem
$exclude = validate_regex($exclude) if defined($exclude);
$hadoop_bin  = which($hadoop_bin, 1);
$hadoop_bin  =~ /\b\/?hadoop$/ or die "invalid hadoop program '$hadoop_bin' given, should be called hadoop!\n";
vlog_options "path", $path;
vlog_options "expunge", $expunge ? "true" : "false";
vlog_options "hadoop path", $hadoop_bin;
vlog2;

set_timeout();

my $cmd = "hadoop fs -lsr '$path'";
my $fh = cmd("$cmd | ") or die "ERROR: $? returned from \"$cmd\" command: $!\n";
my @files = ();
my $now   = time || die "Failed to get epoch timestamp\n";
my $file_count    = 0;
my $files_removed = 0;
while (<$fh>){
    print "output: $_" if $verbose > 3;
    chomp;
    my $line = $_;
    $line =~ /^Found\s\d+\sitems/ and next;
    if($line =~ /^([d-])[r-][w-][x-][r-][w-][x-][r-][w-][x-]\s+(?:\d+|-)\s+\w+\s+\w+\s+\d+\s+(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})\s+($filename_regex)$/){
        my $dir      = $1;
        next if $dir eq "d"; # Not supporting dirs as there is no -rmdir and it would require a dangerous -rmr operation and should therefore be done by hand
        $file_count++;
        my $year     = $2;
        my $month    = $3;
        my $day      = $4;
        my $hour     = $5;
        my $min      = $6;
        my $filename = $7;
        my $tstamp   = timegm(0, $min, $hour, $day, $months{$month}, $year-1900) || die "$progname: Failed to convert timestamp $year-$month-$day $hour:$min for comparison\n";
        if( ($now - $tstamp ) > ($days * 86400) ){
            next if (defined($exclude) and $filename =~ /$exclude/);
            push(@files, $filename); 
            $files_removed++;
        }
    } else {
        warn "$progname: WARNING - failed to match line from hadoop output: \"$line\"\n";
    }
    if(scalar @files >= 20){
        $cmd = "$echo echo hadoop fs -rm '" . join("' '", @files) . "'";
        system($cmd) and die "ERROR: $? returned from \"hadoop fs -rm\" command: $!\n";
        @files = ();
    }
}

if($expunge){
    $cmd = "$echo echo hadoop fs -expunge";
    system($cmd) and warn "$progname: Expunge failed, returned $? from \"$cmd\" command: $!\n";
}
$msg = "$progname Complete - %d files checked, %d files older than %s days " . ($echo ? "" : "removed") . "\n";
printf($msg, $file_count, $files_removed, $days);
