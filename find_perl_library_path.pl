#!/usr/bin/perl
#
#  Author: Hari Sekhon
#  Date: 2019-09-27
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

$DESCRIPTION = "

Simple tool to print the local path to one or more libraries given as arguments

Useful for finding where things are installed on different operating systems like Mac vs Linux

Tested on Perl 5.x on Mac and Linux

";

$VERSION = "0.1.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}

if(not @ARGV or @ARGV < 1){
    # doing this as a sub has a prototype mismatch if you import anything that has the same sub name, eg. usage() from HariSekhonUtils.pm
    #usage;
    my $progname = basename $0;
    my $description = $main::DESCRIPTION;
    $description =~ s/^\s*//;
    $description =~ s/\s*$//;
    print "$description\n\n\n";
    print "usage: $progname <library1> [<library2> <library3>...]\n\n";
    exit 3;

}

my $exitcode = 0;
foreach my $module (@ARGV){
    #$module =~ /^([A-Za-z0-9:]+)$/ or next
    #$module = $1;
    my $path = $module;
    $path =~ s/::/\//g;
    # normalize between adding .pm or omitting it for each module
    $path =~ s/.pm$//;
    $path =~ s/$/.pm/;
    eval {
        require $path;
        import $module;
    };
    if($@){
        print STDERR  "perl module '$module' not found: $@";
        $exitcode = 2;
        next;
    }
    if(exists $INC{$path}){
        print "$INC{$path}\n";
    } else {
        $exitcode = 3;
    }
}
exit $exitcode
