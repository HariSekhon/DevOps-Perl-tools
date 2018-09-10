#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2018-09-09 22:31:41 +0100 (Sun, 09 Sep 2018)
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

$DESCRIPTION="Strip ANSI Escape Codes from Text String input

Works as a standard unix filter program, reading from file arguments or standard input and printing to standard output
";

# Simple program to expose strip_ansi_escape_codes utility function as a general purpose command line unix filter program

$VERSION = "0.1";

use strict;
use warnings;
use utf8;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $file;

%options = (
    "f|files=s"     => [ \$file, "File(s) to read as input to strip escape codes, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
);

get_options();

my @files = parse_file_option($file, "args are files");

if(@files){
    foreach my $file (@files){
        my $fh = open_file $file;
        while(<$fh>){ print strip_ansi_escape_codes($_) }
    }
} else {
    while(<STDIN>){ print strip_ansi_escape_codes($_) }
}
