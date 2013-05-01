#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2012-12-29 10:53:23 +0000 (Sat, 29 Dec 2012)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Filter program to print net line additions/removals from diff / patch files or stdin";

# This is a rewrite of a shell version I used for a few years in my extensive
# and borderline ridiculously over developed but immensely cool bashrc
# (nearly 4500 lines at the time I've split this off)
# (6500 with aliases files + an additional 21,000 lines of supporting scripts)
#
# It's at least 5 times faster than the shell version
# it's easier to control matching programatically and
# it leverages my personal perl library's validation functions

# TODO: use counters so that I don't discount 2 removals for 1 addition etc

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$usage_line = "usage: $progname [patchfile1] [patchfile2] ...";

my $fh;
my $additions_only;
my $removals_only;
my $blocks;
my $add_prefix;
my $remove_prefix;

%options = (
    "a|additions-only"   => [ \$additions_only, "Show only additions" ],
    "r|removals-only"    => [ \$removals_only, "Show only removals" ],
    "b|blocks"           => [ \$blocks, "Show changes in blocks of additions first and then removals" ],
);

get_options();

$additions_only and $removals_only and usage "--additions-only and --removals-only are mutually exclusive options!";

if(@ARGV){
    foreach(@ARGV){
        $_ eq "-" and next;
        validate_file($_);
    }
};

sub diffnet {
    my $fh       = shift;
    my $filename = shift;
    my %additions;
    my %removals;
    while(<$fh>){
        unless(defined($add_prefix)){
            if(/^([\+\>])/){
                $add_prefix = $1;
            }
        }
        unless(defined($remove_prefix)){
            if(/^([\-\<])/){
                $remove_prefix = $1;
            }
        }
        next if /^[\+\-]{3}/;
        #print if /^\+{3}/;
        #print if /^\-{3}/;
        if(/^[\+\>]/){ # and not /^\+{3}\s[ab]\/$filename/){
            $additions{$.} = substr($_, 1);
            next;
        } elsif(/^[\-<]/){ # and not /^\-{3}\s[ab]\/$filename/){
            $removals{$.}  = substr($_, 1);
            next;
        } else {
            vlog3 "skipping line: $_";
        }
    }
    if($blocks or $additions_only or $removals_only){
        unless($removals_only){
            foreach my $i (sort {$a <=> $b} keys %additions){
                print "$add_prefix$additions{$i}" unless grep { $_ eq $additions{$i} } values %removals;
            }
        }
        unless($additions_only){
            foreach my $i (sort {$a <=> $b} keys %removals){
                print "$remove_prefix$removals{$i}" unless grep { $_ eq $removals{$i} } values %additions;;
            }
        }
    } else {
        #my $max_addition_lineno = (sort {$a <=> $b} keys %additions)[0] || 0;
        #my $max_removal_lineno  = (sort {$a <=> $b} keys %removals)[0]  || 0;
        #my $max_lineno          = $max_addition_lineno > $max_removal_lineno ? $max_addition_lineno : $max_removal_lineno;
        my @changes = sort {$a <=> $b} ( keys %additions, keys %removals );
        @changes or return;
        foreach my $i ( uniq_array(@changes) ){
            if(defined($additions{$i}) and defined($removals{$i})){
                die "code error: have stored line number $i against both addition and removal, not possible!";
            } elsif(defined($additions{$i})){
                print "$add_prefix$additions{$i}" unless grep { $_ eq $additions{$i} } values %removals;
            } elsif(defined($removals{$i})){
                print "$remove_prefix$removals{$i}" unless grep { $_ eq $removals{$i} } values %additions;
            } else {
                die "code error: line number $i was not found in either additions or removals hash";
            }
        }
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
