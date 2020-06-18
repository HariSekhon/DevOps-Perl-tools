#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2012-02-02 13:24:30 +0000 (Thu, 02 Feb 2012)
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

$DESCRIPTION = "Arbitrary locking utility

Gains an exclusive lock and executes the given command, then releases the lock

Aborts without executing the command if the lock is already in use to prevent commands clashing";

$VERSION = "1.2.1";

use strict;
use warnings;
use File::Basename;
use Getopt::Long qw(:config bundling);
use Fcntl ':flock';

BEGIN {
    delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
    $ENV{'PATH'} = '/bin:/usr/bin';
    $| = 1;
}

my $progname = basename $0;

my $command;
my $default_timeout = 10;
my $help;
my $lockfile;
my $max_timeout = 3600;
my $timeout = $default_timeout;
my $verbose = 0;
my $version;

sub vlog{
    print "@_\n" if $verbose;
}

sub usage {
    print STDERR "@_\n\n" if @_;
    print STDERR "$main::DESCRIPTION\n\n" if $main::DESCRIPTION;
    print STDERR "usage: $progname [ options ]

    -c --command        Command to run if lock succeeds
    -l --lockfile       Lockfile to use. This will be created if it doesn't exist, will not be overwritten or appended to and will not be removed for safety
    -t --timeout        Timeout in secs (default $default_timeout)
    -v --verbose        Verbose mode
    -V --version        Print version and exit
    -h --help --usage   Print this help
\n";
    exit 3;
}

GetOptions (
            "c|cmd|command=s"   => \$command,
            "l|lock|lockfile=s" => \$lockfile,
            "h|help|usage"      => \$help,
            "t|timeout=i"       => \$timeout,
            "v|verbose+"        => \$verbose,
            "V|version"         => \$version,
           ) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";
defined($command)  || usage "command not specified";
defined($lockfile) || usage "lockfile not specified";

# Allow all chars for cmd since this is the point of the code
$command =~ /^(.+)$/;
$command = $1;
$lockfile =~ /^([\/\w\s_\.\*\+-]+)$/ or die "Invalid lockfile specified, did not match regex\n";
$lockfile = $1;
$timeout =~ /^\d+$/ || usage "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= $max_timeout) || usage "timeout value must be between 1 - $max_timeout secs\n";

vlog "verbose mode on";
$SIG{ALRM} = sub {
    die "timed out after $timeout seconds\n";
};
vlog "setting timeout to $timeout secs\n";
alarm($timeout);

my $tmpfh;
if(-f $lockfile){
    vlog "opening lock file '$lockfile'\n";
    open $tmpfh, "<", $lockfile or die "Error: failed to open lock file '$lockfile': $!\n";
} else {
    vlog "creating lock file '$lockfile'\n";
    open $tmpfh, "+>", $lockfile or die "Error: failed to create lock file '$lockfile': $!\n";
}
flock($tmpfh, LOCK_EX | LOCK_NB) or die "Failed to aquire a lock on lock file '$lockfile', another process must be running, aborting\n";
system($command);
exit $? >> 8;
