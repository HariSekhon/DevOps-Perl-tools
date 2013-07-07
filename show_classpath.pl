#!/usr/bin/perl -T
#
#   Author: Hari Sekhon
#   Date: 2013-02-11 11:50:00 +0000 (Mon, 11 Feb 2013)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4:et

$DESCRIPTION = "Program to print all the command line classpaths of Java processes based on a given regex.

Credit to Clint Heath & Linden Hillenbrand @ Cloudera for giving me this idea";

$VERSION = 0.3;

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
    "C|command_regex=s" => [ \$command_regex, "Command regex (PCRE format). Default \"\" shows all java processes" ],
    "s|stdin"           => [ \$stdin,         "Read process 'command +args' strings one per line from stdin (else spawns 'ps -ef')" ],
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

sub show_jinfo_classpath($){
    my $cmd = shift;
    $cmd =~ /\bjava\b/ or return;
    $cmd =~ s/\s-(?:cp|classpath)(?:\s+|=)([^\s+]+)(?:\s|$)/ <CLASSPATHS> /;
    print "\ncommand:  $cmd\n\n";
    # support ps -ef and ps aux type inputs for convenience
    if($cmd =~ /^\w+\s+(\d+)\s+\d+(?:\.\d+)?\s+\d+(?:\.\d+)?/){
    } elsif($cmd =~ /^(\d+)\s+\w+\s+(?:$filename_regex\/)?java.+$/){
    } else {
        die "Invalid input to show_jinfo_classpath, expecting '<pid> <user> <cmd>' or 'ps -ef' or 'ps aux' input\n";
    }
    my $pid = $1;
    my @output = cmd("jinfo $pid");
    my $found_classpath = 0;
    foreach(@output){
        if(/error/i){
            die "jinfo error attaching to process id $pid\n$_\n";
        }
        /^java.class.path\s*=\s*/ or next;
        s/^java.class.path\s*=\s*//;
        my $count = 0;
        foreach(split(":", $_)){
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
}

my $fh;
if($stdin){
    $fh = *STDIN;
} else {
    open $fh, "ps -e -o pid,user,command |";
}
while(<$fh>){
    chomp;
    if(/\bjava\s.*$command_regex/io){
        #show_cli_classpath($_);
        show_jinfo_classpath($_);
        print "="x80 . "\n"; 
    }
}
