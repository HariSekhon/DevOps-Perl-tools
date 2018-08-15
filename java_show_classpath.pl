#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-02-11 11:50:00 +0000 (Mon, 11 Feb 2013)
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

$DESCRIPTION = "Program to print all the command line classpaths of Java processes based on a given regex.

Credit to Clint Heath & Linden Hillenbrand @ Cloudera for giving me this idea";

$VERSION = 0.4;

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

$ENV{'PATH'} = '/bin:/usr/bin:/usr/java/default/bin:/System/Library/Frameworks/JavaVM.framework/Versions/Current/Commands';

my $command_regex = "";
my $stdin = 0;

%options = (
    "C|command_regex=s" => [ \$command_regex, "Regex of classname for JPS or command for 'ps -ef' or 'ps aux' if piping in 'ps -ef' or 'ps aux' input. Default \"\" shows all java processes" ],
    "s|stdin"           => [ \$stdin,         "Read process one per line from stdin (should be in format of 'jps', 'ps -ef', or 'ps aux' command outputs)" ],
);

get_options();

if (@ARGV == 0){
} elsif (@ARGV == 1 and $command_regex eq ""){
    $command_regex = $ARGV[0];
} else {
    usage;
}

if(defined($command_regex)){
    if(! eval { qr/$command_regex/ }){
        die "invalid command regex supplied: $command_regex\n";
    }
}

# XXX: this is truncated to 4096 chars which for programs with very long cli classpaths is a hard coded kernel problem
sub show_cli_classpath($){
    my $cmd = shift;
    $cmd =~ /\bjava\b/ or return;
    ( my $args = $cmd ) =~ s/.*?java\s+//;;
    $cmd =~ s/\s-(?:cp|classpath)(?:\s+|=)([^\s+]+)(?:\s|$)/ <CLASSPATHS> /;
    print "\ncommand:  $cmd\n\n";
    my $count = 0;
    if($args =~ /\s-(?:cp|classpath)(?:\s+|=)([^\s+]+)(?:\s|$)/i){
        foreach(split(/\:/, $1)){
            next if /^\s*$/;
            print "classpath:  $_\n";
            $count++;
        }
    }
    print "\n" if $count;
    plural $count;
    print "$count classpath$plural found\n\n";
}

# the blank case is an embedded JVM with no main classname, ie Impalad's embedded JVM in C++ for HDFS calls
my $jps_regex = qr/^(\d+)\s+(\w*)$/;

sub show_jinfo_classpath($){
    my $cmd = shift;
    my $pid;
    if($cmd =~ $jps_regex){
        $pid = $1;
        return if $2 eq "Jps";
        unless($2){
            $cmd .= "<embedded JVM no classname from JPS output>";
        }
        debug "JPS input detected";
        print "JPS:     $cmd\n";
        print "command: " . `ps h -fp $pid` . "\n\n";
    } else {
        unless($cmd =~ /\bjava\b/){
            vlog2 "skipping $cmd since it doesn't match /\\bjava\\b/";
            return;
        }
        $cmd =~ s/\s-(?:cp|classpath)(?:\s+|=)([^\s+]+)(?:\s|$)/ <CLASSPATHS> /;
        print "\ncommand:  $cmd\n\n";
        # support ps -ef and ps aux type inputs for convenience
        if($cmd =~ /^\s*\w+\s+(\d+)\s+\d+(?:\.\d+)?\s+\d+(?:\.\d+)?/){
            debug "ps -ef input detected";
        } elsif($cmd =~ /^\s*(\d+)\s+\w+\s+(?:$filename_regex\/)?java.+$/){
            debug "ps aux input detected";
        } else {
            die "Invalid input to show_jinfo_classpath, expecting '<pid> <classname>' or '<pid> <user> <cmd>' or 'ps -ef' or 'ps aux' input\n";
        }
        $pid = $1;
    }
    my @output = cmd("jinfo $pid");
    my $found_classpath = 0;
    foreach(@output){
        if(/error/i){
            die "jinfo error attaching to process id $pid\n$_\n";
        }
        /^java.class.path\s*=\s*/ or next;
        s/^java.class.path\s*=\s*//;
        my $count = 0;
        foreach(split(/:/, $_)){
            next if /^\s*$/;
            print "classpath:  $_\n";
            $count++;
        }
        print "\n" if $count;
        #print "\n" . "="x80 . "\n";
        plural $count;
        print "$count classpath$plural found\n\n";
        $found_classpath = 1;
        last;
    }
    $found_classpath or die "Failed to find java classpath in output from jinfo!\n";
    print "="x80 . "\n";
}

my $fh;
if($stdin){
    $fh = *STDIN;
} else {
    unless(open $fh, "jps |"){
        warn "\nWARNING: jps failed, perhaps not in \$PATH? (\$PATH = $ENV{PATH})\n";
        warn "\nWARNING: Falling back to ps command\n\n";
        open $fh, "ps -e -o pid,user,command |";
    }
}
while(<$fh>){
    chomp;
    debug "input: $_";
    if($_ =~ $jps_regex){
        debug "JPS process detected";
        if($command_regex){
            if($2 =~ /$command_regex/io){
                show_jinfo_classpath($_);
            }
        } else {
            show_jinfo_classpath($_);
        }
    } elsif(/\bjava\s.*$command_regex/io){
        debug "Java command detected";
        #show_cli_classpath($_);
        show_jinfo_classpath($_);
    }
}
