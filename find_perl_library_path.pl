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

$DESCRIPTION = "Prints the location of Perl modules given as arguments

Tested on Mac OS X and Linux";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}

my $exitcode = 0;
foreach my $module (@ARGV){
    #$module =~ /^([A-Za-z0-9:]+)$/ or next
    #$module = $1;
    my $path = $module;
    $path =~ s/::/\//g;
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
