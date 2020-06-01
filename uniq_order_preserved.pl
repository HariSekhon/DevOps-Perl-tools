#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-02-07 16:06:33 +0000 (Sat, 07 Feb 2015)
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

$DESCRIPTION = "Filter program to print only non-repeated lines in input - unlike the unix command 'uniq' lines do not have to be adjacent, this is order preserving compared to 'sort | uniq'. I rustled this up quickly after needing to parse unique missing modules for building but maintaining order as some modules depend on others being built first

Works as a standard unix filter program taking either standard input or files supplied as arguments

Since this must maintain unique lines in memory for comparison, do not use this on very large files/inputs

Tested on Mac and Linux
";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$usage_line = "usage: $progname [file1] [file2] ...";

my $fh;
my $ignore_case;
my $ignore_whitespace;
my %uniq;

%options = (
    "i|ignore-case"       => [ \$ignore_case,       "Ignore case in comparisons" ],
    "w|ignore-whitespace" => [ \$ignore_whitespace, "Ignore whitespace in comparisons" ],
);
splice @usage_order, 6, 0, qw/ignore-case ignore-whitespace/;

get_options();

if(@ARGV){
    foreach(@ARGV){
        $_ eq "-" and next;
        validate_file($_);
    }
};

sub transformations ($) {
    my $string = shift;
    if($ignore_case){
        $string = lc $string;
    }
    if($ignore_whitespace){
        $string =~ s/\s+//g;
    }
    return $string;
}

sub uniq($){
    my $line = $_[0];
    if(defined($uniq{$line})){
        return 0;
    } else {
        $uniq{$line} = 1;
    }
    return 1;
}

sub print_uniq ($) {
    my $fh = shift;
    my $string2;
    while(<$fh>){
        $string2 = transformations($_);
        print $_ if uniq ($string2);
    }
}


if(@ARGV){
    foreach(@ARGV){
        if($_ eq "-"){
            $fh = *STDIN;
        } else {
            $fh = open_file $_;
        }
        print_uniq($fh);
    }
} else {
    print_uniq(*STDIN);
}
