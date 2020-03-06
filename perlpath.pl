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

Simple tool to print the Perl \@INC path, one per line

Perl path \@INC may be different between perl and perl -T runs as taint mode prevents loading \$PERL5LIB

Tested on Perl 5.x on Mac and Linux

";

$VERSION = "0.2.0";

use strict;
use warnings;
use File::Basename;
#BEGIN {
#    use File::Basename;
#    use lib dirname(__FILE__) . "/lib";
#}

sub usage(){
    my $progname = basename $0;
    my $description = $main::DESCRIPTION;
    $description =~ s/^\s*//;
    $description =~ s/\s*$//;
    print "$description\n\n\n";
    print "usage: $progname\n\n";
    exit 3;

}


if(@ARGV){
    usage;
}

print join("\n", @INC) . "\n";
