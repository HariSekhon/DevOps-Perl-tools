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

$VERSION = "0.3.1";

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

my $days  = 0;
my $hours = 0;
my $mins  = 0;
my $exclude;
my $skipTrash = "";
my $rm = 0;

set_timeout_max(86400);    # 1 day max -t timeout
set_timeout_default(1800); # 30 mins. hadoop fs -lsr /tmp took 6 minutes to list 1720943 files/dirs on my test cluster!

my %months = (
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
);

%options = (
    "d|days=i"      =>  [ \$days,       "Number of days after which to delete files" ],
    "H|hours=i"     =>  [ \$hours,      "Number of hours after which to delete files" ],
    "m|mins=i"      =>  [ \$mins,       "Number of minutes after which to delete files" ],
    "p|path=s"      =>  [ \$path,       "Path for which to remove old files (default: $DEFAULT_PATH)" ],
    "e|exclude=s"   =>  [ \$exclude,    "Regex of files to exclude from being deleted" ],
    "rm"            =>  [ \$rm,         "Actually launch the hadoop fs -rm commands on the files, by default this script only prints the hadoop fs -rm commands. WARNING: only use this switch after you have checked what the list of files to be removed is, otherwise you may lose data" ],
    "skipTrash"     =>  [ \$skipTrash,  "Skips moving files to HDFS Trash, reclaims space immediately" ],
    "hadoop-bin=s"  =>  [ \$hadoop_bin, "Path to 'hadoop' command if not in \$PATH" ],
);
@usage_order = qw/days hours mins path exclude rm skipTrash hadoop-bin/;
get_options();

my $echo = "echo";
if ($rm and not $debug){
    $echo = ""; # actually run the hadoop fs -rm command instead of just echo'ing it out
}
$skipTrash = "-skipTrash" if $skipTrash;

$days    = validate_float($days,  0, 3650, "days");
$hours   = validate_float($hours, 0, 23,   "hours");
$mins    = validate_float($mins,  0, 59,   "mins");
my $max_age_secs = ($days * 86400) + ($hours * 3600) + ($mins * 60);
usage "must specify a total max age > 5 minutes" if ($max_age_secs < 300);
$path        = validate_filename($path, undef, "path"); # because validate_dir[ectory] checks the directory existance on the local filesystem
$exclude     = validate_regex($exclude) if defined($exclude);
$hadoop_bin  = which($hadoop_bin, 1);
$hadoop_bin  =~ /\b\/?hadoop$/ or die "invalid hadoop program '$hadoop_bin' given, should be called hadoop!\n";
vlog_options "rm",          $rm        ? "true" : "false";
vlog_options "skipTrash",   $skipTrash ? "true" : "false";
vlog_options "hadoop path", $hadoop_bin;
vlog2;

set_timeout();

my $cmd   = "hadoop fs -ls -R '$path'";
my $fh    = cmd("$cmd | ") or die "ERROR: $? returned from \"$cmd\" command: $!\n";
my @files = ();
my $now   = time || die "Failed to get epoch timestamp\n";
my $file_count    = 0;
my $files_removed = 0;
while (<$fh>){
    print "output: $_" if $verbose >= 3;
    chomp;
    my $line = $_;
    $line =~ /^Found\s\d+\sitems/ and next;
    if($line =~ /^([d-])$rwxt_regex\s+(?:\d+|-)\s+\w+\s+\w+\s+\d+\s+(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})\s+($filename_regex)$/){
        my $dir      = $1;
        next if $dir eq "d"; # Not supporting dirs as there is no -rmdir and it would require a dangerous -rmr operation and should therefore be done by hand
        $file_count++;
        my $year     = $2;
        my $month    = $3;
        my $day      = $4;
        my $hour     = $5;
        my $min      = $6;
        my $filename = $7;
        $month = $months{$month} if grep { $month eq $_} keys %months;
        my $tstamp   = timelocal(0, $min, $hour, $day, $month-1, $year) || die "$progname: Failed to convert timestamp $year-$month-$day $hour:$min for comparison\n";
        if( ($now - $tstamp ) > $max_age_secs){
            next if (defined($exclude) and $filename =~ /$exclude/);
            # Some additional safety stuff, do not mess with /tmp/mapred or /hbase !!!! or .Trash
            next if ($filename =~ /^\/(?:tmp\/mapred|hbase)\//i or
                     $filename =~ /\.Trash\//);
            push(@files, $filename);
            $files_removed++;
        }
    } else {
        warn "$progname: WARNING - failed to match line from hadoop output: \"$line\"\n";
    }
    if(@files){
        $cmd = "$echo hadoop fs -rm $skipTrash '" . join("' '", @files) . "'";
        system($cmd) and die "ERROR: $? returned from \"hadoop fs -rm\" command: $!\n";
        @files = ();
    }
}

plural($file_count);
$msg = "$progname Complete - %d file$plural checked, ";
plural($files_removed);
$msg .= "%d file$plural older than %s days %s hours %s mins " . ($echo ? "" : "removed") . "\n";
printf($msg, $file_count, $files_removed, $days, $hours, $mins);
