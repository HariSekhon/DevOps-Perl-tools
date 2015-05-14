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

Does not uppercase letters immediately after an apostrophe or a dot except for dotted acronyms (2 or more letters preceeded by dots immediately following each other).

Works as a standard unix filter program, taking files are arguments or assuming input from standard input and printing to standard output.

Can optionally also replace specific phrases using a phrases.txt file where the format is either a correctly cased phrase or a case insensitive regex followed by ' => ' and then a string replacement (preserves whitespace in string):

# comment, camel case myString exactly as written below in -r file.txt
myString
# another comment, make this phrase appear with this exact case, to emphasize the dark side of the force...
Something Something DARK Side
regex1  => MY_String
regex2  => AnotherString
...
";

$VERSION = "0.4";

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
    "r|recase=s"  => [ \$recase,      "ReCase words/phrases from a text file, see full --help summary for description of format (optional)" ],
);
@usage_order = qw/files lowercase recase/;

get_options();

my @files = parse_file_option($file, "args are files");

my %recase_regexes;
my @recase_phrases;
if($recase){
    my $fh = open_file $recase;
    my $regex;
    while (<$fh>){
        chomp;
        s/#.*//;
        /^\s*$/ and next;
        my @parts = split(/\s*=>\s*/, $_, 2);
        unless(isRegex($parts[0])){
            warn "skipping invalid regex in file '$recase': $parts[0]\n";
            next;
        }
        my $replacement;
        if(defined($parts[1])){
            # allow first part to be regex
            unless($parts[0] = isRegex($parts[0])){
                warn "ignoring invalid regex '$parts[0]'\n";
                next;
            }
            $recase_regexes{$parts[0]} = $parts[1];
            #vlog3 "regex is $parts[0] ... => ... $parts[1]";
        } else {
            unless($parts[0] =~ /^[\w\s\.\'\"-]+$/){
                warn "skipping invalid phrase string in file '$recase': '$parts[0]' (must be an alphanumeric string - may also contain dots, quotes and dashes only, must not be a regex unless followed by '=> someString'\n";
                next;
            }
            push(@recase_phrases, $parts[0]); 
        }
    }
}

sub titlecase ($) {
    my $string = shift;
    $string = lc $string if $lowercase;
    # exclude letters immediately preceeded by a dot such as file extensions
    $string =~ s/\b(?<![\.'])([A-Za-z])/\U$1/g;
    # uppercase acronyms to correct for the above exception for file extensions
    $string =~ s/(\s[A-Za-z](?:\.[A-Za-z])+)/\U$1/g;
    if(@recase_phrases){
        foreach my $phrase (@recase_phrases){
            #vlog3 "trying phrase $phrase\n";
            $string =~ s/\b($phrase)\b/$phrase/gi and vlog3 "replaced phrase $phrase";
        }
    }
    if(%recase_regexes){
        foreach my $regex (sort keys %recase_regexes){
            $string =~ s/\b(?-i:$regex)\b/$recase_regexes{$regex}/g and vlog3 "replaced regex '$regex' with '$recase_regexes{$regex}'";
        }
    }
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
