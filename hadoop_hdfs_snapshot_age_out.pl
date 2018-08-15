#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Forked from file retention policy script "hadoop_hdfs_retention_policy.pl"
#  Original Date: 2013-01-14 20:50:13 +0000 (Mon, 14 Jan 2013)
#  Date: 2015-05-08
#
#  https://github.com/harisekhon/devops-perl-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# forked from hadoop_hdfs_file_age_out.pl

$DESCRIPTION = "Prints snapshots that match a regex pattern or are older than the specified days. Requires snapshots to be named with 'YYYY-MM-DD' somewhere in the name since snapshot timestamps have proven to be inaccurate (eg. I've observed older snapshots with new timestamps on the .snapshot/<name> directory). Deletes those matching snapshots if specifying --delete (use without --delete to see what it would do first!)

Don't forget to kinit first if running on a kerberized cluster!

Tested on Hortonworks HDP 2.2";

$VERSION = "0.2";

use strict;
use warnings;
use Time::Local;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

$ENV{"PATH"} .= ":/opt/hadoop/bin:/usr/local/hadoop/bin";

my $default_hdfs_bin = "hdfs";
my $hdfs = $default_hdfs_bin;

my $path; # don't set this, need to check if user did or used @ARGV

my $days;
my $include;
my $exclude;
my $delete;
my $Xmx;
my $monthly;
my $yearly;

set_timeout_max(36000);    # 10 hours max -t timeout
set_timeout_default(3600); # 1 hour by default

%options = (
    "d|days=i"      =>  [ \$days,       "Select snapshots older than this many days (requires snapshots be have YYYY-MM-DD included in the name)" ],
    "i|include=s"   =>  [ \$include,    "Include Regex of snapshottable directories, for optional filtering" ],
    "e|exclude=s"   =>  [ \$exclude,    "Exclude Regex of snapshottable directories, optional, takes priority over --include" ],
    "delete"        =>  [ \$delete,     "Delete matching snapshots older than given number of days, by default this script only prints the hadoop commands to remove them for safety. WARNING: only use this switch after you have checked what the list of snapshots to be removed is" ],
    "hdfs-bin=s"    =>  [ \$hdfs,       "Path to 'hdfs' command if not in \$PATH" ],
    "save-monthly"  =>  [ \$monthly,    "Leave the last snapshot of each month (last in lexical order of the last day found)" ],
    "save-yearly"   =>  [ \$yearly,     "Leave the last snapshot of each year (last snapshot found in each calendar year)" ],
    #"Xmx=s"        =>  [ \$Xmx,        "Max Heap to assign to the 'hadoop' or 'hdfs' command in MB, must be an integer, units cannot be specified" ],
);
@usage_order = qw/days include exclude delete save-monthly save-yearly hdfs-bin/;

get_options();

my $print_only = 1;
if ($delete and not $debug){
    $print_only = 0; # actually run the snapshot deletion commands of just printing them out
}
$days = validate_float($days,  "days",  0, 3650);
if(defined($include)){
    $include     = validate_regex($include, "include");
    $include     = qr/$include/o;
}
if(defined($exclude)){
    $exclude     = validate_regex($exclude, "exclude");
    $exclude     = qr/$exclude/o;
}
if($Xmx){
    $Xmx =~ /^(\d+)$/ or usage "-Xmx must be an integer representing the number of MB to allocate to the Heap";
    $Xmx = $1;
    vlog_option "Xmx (Max Heap MB)", $Xmx;
}
$hdfs = validate_program_path($hdfs, "hdfs");
vlog_option_bool "delete", $delete;
vlog2;

set_timeout();

go_flock_yourself();
vlog2;

vlog2 "finding snapshottable dirs in HDFS";
my $cmd_xmx = "";
if($Xmx){
    $cmd_xmx = "HADOOP_HEAPSIZE='$Xmx'";
}
my $cmd = "$cmd_xmx hdfs lsSnapshottableDir";
my $fh  = cmd("$cmd | ", 1) or die "ERROR: $? returned from \"$cmd\" command: $!\n";
my @snapshot_dirs = ();
while(<$fh>){
    chomp;
    vlog3 "output: $_";
    my $line = $_;
    if($line =~ /^[d-]$rwxt_regex\s+(?:\d+|-)\s+[\w-]+\s+[\w-]+\s+\d+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+\d+\s+\d+\s+($dirname_regex)\s*$/){
        my $dir = $1;
        if ($dir =~ qr{
                        [\'\"\`] |
                        \$\(
                      }ix){
            die "dangerous chars found in snapshottable dir '$dir', aborting!\n";
        }
        push(@snapshot_dirs, $dir);
    } else {
        die "unrecognized output line getting list of snapshottable dirs '$line'\n";
    }
}
vlog2;
@snapshot_dirs or die "No snapshottable dirs found in HDFS\n";

my $snapshot_count     = 0;
my $snapshots_removed  = 0;
my $included_count     = 0;
my $excluded_count     = 0;

my @time_parts = localtime();
printf("Finding snapshots $days days older in their name than today %04d-%02d-%02d\n", 1900 + $time_parts[5], $time_parts[4], $time_parts[3]);
my $today = timelocal(0, 0, 0, $time_parts[3], $time_parts[4], $time_parts[5]);
my $days_secs = $days * 86400;
vlog2;

sub process_snapshots($){
    my $dir = shift;
    $included_count++;
    $dir or code_error("dir not defined when calling process_snapshots()");
    isDirname($dir) or code_error("invalid dir '$dir' passed to process_snapshots()");
    vlog "processing snapshot list for dir '$dir'";
    my %snapshots_by_date;
    $cmd = "$cmd_xmx hdfs dfs -ls '$dir/.snapshot'";
    my $fh = cmd("$cmd | ", 1) or die "ERROR: $? returned from \"$cmd\" command: $!\n";
    while (<$fh>){
        chomp;
        vlog3 "output: $_";
        my $line = $_;
        $line =~ /^Found\s\d+\sitems/ and next;
        if($line =~ /^([d-])$rwxt_regex\+?\s+(?:\d+|-)\s+[\w-]+\s+[\w-]+\s+\d+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+($dirname_regex)$/){
            my $dir_type = $1;
            my $snapshot_name = basename($2);
            if($dir_type ne "d"){
                # assert this should never happen
                die "non-directory found! ('$dir'). see -vvv output and raise a ticket at https://github.com/harisekhon/devops-perl-tools/issues\n";
            }
            if ($snapshot_name =~ qr{
                                      [\'\"\`] |
                                      \$\(
                                    }ix){
                die "dangerous chars found in snapshot name '$snapshot_name', aborting!\n";
            }
            $snapshot_count++;
            my ($year, $month, $day);
            if($snapshot_name =~ /(\d{4})-(\d{2})-(\d{2})/){
                $year  = $1;
                $month = $2;
                $day   = $3;
            } else {
                warn "skipping snapshot without date in name '$snapshot_name'\n";
                next;
            }
            $snapshots_by_date{$year}{$month}{$day}{$snapshot_name}  = 1;
        } else {
            warn "$progname: WARNING - failed to match line from hadoop output: \"$line\"\n";
        }
    }
    if($monthly){
        foreach my $year (sort keys %snapshots_by_date){
            foreach my $month (sort keys %{$snapshots_by_date{$year}}){
                foreach my $day (sort { $b <=> $a } keys %{$snapshots_by_date{$year}{$month}}){
                    foreach my $snapshot (sort { $b <=> $a } keys %{$snapshots_by_date{$year}{$month}{$day}}){
                        vlog2 "leaving last snapshot of month $month: $snapshot";
                        delete $snapshots_by_date{$year}{$month}{$day}{$snapshot};
                        last;
                    }
                    last;
                }
            }
        }
    } elsif ($yearly){
        foreach my $year (sort keys %snapshots_by_date){
            foreach my $month (sort { $b <=> $a } keys %{$snapshots_by_date{$year}}){
                foreach my $day (sort { $b <=> $a } keys %{$snapshots_by_date{$year}{$month}}){
                    foreach my $snapshot (sort { $b <=> $a } keys %{$snapshots_by_date{$year}{$month}{$day}}){
                        vlog2 "leaving last snapshot of year $year: $snapshot";
                        delete $snapshots_by_date{$year}{$month}{$day}{$snapshot};
                        last;
                    }
                    last;
                }
                last;
            }
        }
    }
    my @snapshots_to_delete;
    foreach my $year (sort keys %snapshots_by_date){
        foreach my $month (sort keys %{$snapshots_by_date{$year}}){
            foreach my $day (sort keys %{$snapshots_by_date{$year}{$month}}){
                foreach my $snapshot_name (sort keys %{$snapshots_by_date{$year}{$month}{$day}}){
                    my $datestamp = timelocal(0, 0, 0, $day, $month-1, $year) || die "$progname: Failed to convert datestamp $year-$month-$day for snapshot date comparison of snapshot '$snapshot_name'\n";
                    if( ($today - $datestamp) > $days_secs ){
                        push(@snapshots_to_delete, $snapshot_name);
                    }
                }
            }
        }
    }
    if(@snapshots_to_delete){
        foreach my $snapshot_name (@snapshots_to_delete){
            $snapshots_removed++;
            # Not setting HADOOP_HEAPSIZE here since it should be suffient for such operation one per snapshot
            $cmd = "$hdfs dfs -deleteSnapshot '$dir' '$snapshot_name'";
            if($print_only){
                print "$cmd\n";
            } else {
                print "$cmd\n";
                system($cmd);
                if($? == 0){
                    # OK
                } elsif($? == 33280){
                    die "Control-C\n";
                } else {
                    die "ERROR: $? returned from command \"$cmd\": $!\n";
                }
            }
        }
    }
    vlog2;
}

foreach my $dir (@snapshot_dirs){
    if(defined($exclude) and $dir =~ $exclude){
        $excluded_count += 1;
        next;
    }
    if(defined($include)){
        if($dir =~ $include){
            process_snapshots($dir);
        }
    } else {
        process_snapshots($dir);
    }
}

my $snapshot_dir_count = scalar @snapshot_dirs;
plural $snapshot_dir_count;
$msg = "$progname Complete - $snapshot_dir_count snapshottable dir$plural, ";
plural $included_count;
$msg .= "$included_count dir$plural processed, $excluded_count excluded, ";
plural $snapshot_count;
$msg .= "$snapshot_count snapshot$plural total, ";
plural $snapshots_removed;
$msg .= "$snapshots_removed snapshot$plural older than ";
plural $days;
$msg .= "$days days" . ($print_only ? "" : " removed") . "\n";
warn $msg;
