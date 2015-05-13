#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-05-10 12:07:12 +0100 (Sun, 10 May 2015)
#
#  http://github.com/harisekhon/toolbox
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION="Capitalizes the first letter of each word (eg. to use a sentence as a title).

Does not uppercase letters immediately after a dot except for dotted acronyms (2 or more letters preceeded by dots immediately following each other).

Works as a standard unix filter program, taking files are arguments or assuming input from standard input and printing to standard output.";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $file;
my $lowercase;
my $recase;

%options = (
    "f|files=s"   => [ \$file,        "File(s) to titlecase, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
    "l|lowercase" => [ \$lowercase,   "Lowercase the rest of the letters (optional)" ],
    #"r|recase=s"  => [ \$recase,      "ReCase words/phrases from a text file as they appear in that text file one per line (optional)" ],
);
@usage_order = qw/files lowercase/;

get_options();

my @files = parse_file_option($file, "args are files");

#my @recase_regexes;
#if($recase){
#    my $fh = open_file $recase;
#    $recase_regex = "(?:";
#    while my $regex (<$fh>){
#        push(@recase_regexes, $regex);
#    }
#}

sub titlecase ($) {
    my $string = shift;
    $string = lc $string if $lowercase;
    # exclude letters immediately preceeded by a dot such as file extensions
    $string =~ s/\b(?<![\.'])([A-Za-z])/\U$1/g;
    # uppercase acronyms to correct for the above exception for file extensions
    $string =~ s/(\s[A-Za-z](?:\.[A-Za-z])+)/\U$1/g;
#    if(@recase_regexes){
#        foreach my $regex (@recase_regexes){
#            s/$regex/$regex/ig and last;
#        }
#    }
    print $string;
}

if(@files){
    foreach my $file (@files){
        my $fh = open_file $file;
        while(<$fh>){ titlecase($_) }
    }
} else {
    while(<STDIN>){ titlecase($_) }
}
