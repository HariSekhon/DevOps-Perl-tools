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

# TODO: detect environment of process and print those classpaths as well, can only think how to do this on Linux right now and not portably and no time to think now

$DESCRIPTION = "Program to print all the command line classpaths of Java processes based on a given regex";
$VERSION = "0.2";

use strict;
use warnings;
use File::Basename;
use Getopt::Long qw(:config bundling);

# Make %ENV safer (taken from PerlSec)
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

my $progname = basename $0;

my $command_regex = "";
my $default_timeout = 10;
my $help;
my $stdin = 0;
my $timeout = $default_timeout;
my $verbose = 0;
my $version;

sub vlog{
    print "@_\n" if $verbose;
}

sub usage {
    print "@_\n\n" if @_;
    print "$main::DESCRIPTION\n\n" if $main::DESCRIPTION;
    print "usage: $progname [ options ]

    -C --command        Command regex (PCRE format). Default \"\" shows all java processes
    -s --stdin          Read process command +args string from stdin (else spawns 'ps -ef')
    -t --timeout        Timeout in secs (default $default_timeout)
    -v --verbose        Verbose mode
    -V --version        Print version and exit
    -h --help --usage   Print this help
\n";
    exit 1;
}

GetOptions (
    "h|help|usage"      => \$help,
    "C|command_regex=s" => \$command_regex,
    "s|stdin"           => \$stdin,
    "t|timeout=i"       => \$timeout,
    "v|verbose+"        => \$verbose,
    "V|version"         => \$version,
) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";

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

$timeout =~ /^\d+$/                 || usage "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || usage "timeout value must be between 1 - 60 secs\n";

vlog "verbose mode on";
$SIG{ALRM} = sub {
    die "timed out after $timeout seconds\n";
};
vlog "setting timeout to $timeout secs\n";
alarm($timeout);

sub show_classpath($){
    my $cmd = shift;
    ( my $args = $cmd ) =~ s/.*?java\s+//;;
    $cmd =~ s/\s-(?:cp|classpath)(?:\s+|=)([^\s+]+)\s/ <CLASSPATHS> /;
    print "command:  $cmd\n\n";
    #$args =~ s/.*?java\s+//;
    my $count = 0;
    if($args =~ /\s-(?:cp|classpath)(?:\s+|=)([^\s+]+)\s/i){
        foreach(split(/\:/, $1)){
            print "classpath:  $_\n";
            $count++;
        }
    }
    print "\n" if $count;
    #print "\n" . "="x80 . "\n"; 
    print "$count classpaths found\n\n\n";
}

my $fh;
if($stdin){
    $fh = *STDIN;
} else {
    open $fh, "ps -ef|";
}
while(<$fh>){
    chomp;
    if(/\bjava\s.*$command_regex/io){
        show_classpath($_);
    }
}
