#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-05-10 12:07:12 +0100 (Sun, 10 May 2015)
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

$DESCRIPTION="Capitalizes the first letter of each word (eg. to use a sentence as a title)

Works as a standard unix filter program, reading from file arguments or standard input and printing to standard output

Does not uppercase letters immediately after an apostrophe (unless a/i) or a dot except for dotted acronyms (2 or more letters preceeded by dots immediately following each other).

Can optionally also replace specific phrases using \"-r file.txt\" where the format in file.txt is either a correctly cased phrase or a case insensitive regex followed by ' => ' and then a string replacement (preserves whitespace in string):

# comment, camel case myString exactly as written below in -r file.txt
myString
# another comment, make this phrase appear with this exact case, to emphasize the dark side of the force...
Something Something DARK Side
regex1  => MY_String
regex2  => AnotherString
...

Limitations: cannot use capture references in the regex in -f file.txt. It's really meant more for simpler phrase substitution and I couldn't make this work without some kind of ugly or dangerous hack. A better workaround is to simply call a sed or perl inline afterwards such as:

echo \"catch and reprint any number while capitalizing K eg. 100k\" | titlecase.pl | perl -pe 's/(\\d+)k/\$1K/'
";

$VERSION = "0.5";

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
        my $replacement;
        if(defined($parts[1])){
            # allow first part to be regex
            unless(isRegex($parts[0])){
                warn "ignoring invalid regex in file '$recase': $parts[0]\n";
                next;
            }
            # don't untaint this, was a risky experiment to eval that proved not worthwhile
            #$parts[1] =~ /^(.*)$/;
            #$parts[1] = $1;
            # usig qr// here wraps the regex in (?^: ) which disables case insenstive matching even when the s/$regex/.../gi below uses the i modifier
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
    # catch letters starting words inside single quoted strings, unfortunately matches I'Ll, set {3,} as a workaround
    $string =~ s/'([A-Za-z])([A-Za-z]{3,})/'\u$1$2/g;
    # an exception for 'A Nice Title' since 'A isn't an apostrophe abbrieviation
    $string =~ s/'([ai])/'$1/g;
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
            $string =~ s/$regex/$recase_regexes{$regex}/gi and vlog3 "replaced regex '$regex' with '$recase_regexes{$regex}'";
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
