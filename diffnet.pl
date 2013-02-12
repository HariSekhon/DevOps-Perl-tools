#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2012-12-29 10:53:23 +0000 (Sat, 29 Dec 2012)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Filter program to print net line additions/removals from diff / patches";

# This is a rewrite of a shell version I used for a few years in my extensive
# and borderline ridiculously over developed but immensely cool bashrc
# (nearly 4500 lines at the time I've split this off)
# (6500 with aliases files + an additional 21,000 lines of supporting scripts)
#
# It's at least 5 times faster than the shell version
# it's easier to control matching programatically and
# it leverages my personal perl library's validation functions

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$usage_line = "usage: $progname [patchfile1] [patchfile2] ...";

get_options();

my $fh;

if(@ARGV){
    foreach(@ARGV){
        $_ eq "-" and next;
        validate_file($_);
    }
};


sub diffnet {
    my $fh       = shift;
    my $filename = shift;
    my @additions;
    my @removals;
    while(<$fh>){
        #print if /^\+{3}/;
        #print if /^\-{3}/;
        if(/^\+/){ # and not /^\+{3}\s[ab]\/$filename/){
            push(@additions, substr($_, 1));
            next;
        } elsif(/^\-/){ # and not /^\-{3}\s[ab]\/$filename/){
            push(@removals,  substr($_, 1));
            next;
        }
    }
    foreach my $addition (@additions){
        print "+$addition" unless grep { $_ eq $addition } @removals;
    }
    foreach my $removal (@removals){
        print "-$removal"  unless grep { $_ eq $removal  } @additions;
    }
}


if(@ARGV){
    foreach(@ARGV){
        if($_ eq "-"){
            $fh = *STDIN;
        } else {
            $fh = open_file $_;
        }
        diffnet $fh, $_;
    }
} else {
    diffnet *STDIN;
}
