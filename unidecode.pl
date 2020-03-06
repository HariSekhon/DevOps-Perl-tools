#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2012-04-06 21:01:42 +0100 (Fri, 06 Apr 2012)
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

$DESCRIPTION="Converts UTF characters to ASCII

Works as a standard unix filter program, reading from file arguments or standard input and printing to standard output

Known Issues: uses the Text::Unidecode CPAN module, which seems to convert unknown chars to \"a\"

See also unidecode.py (pip install unidecode) which contains a CLI program to do this";

$VERSION = "0.6.3";

use strict;
use warnings;
use utf8;
#use Data::Dumper;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Text::Unidecode; # For changing unicode to ascii

my $file;

%options = (
    "f|files=s"     => [ \$file, "File(s) to unidecode, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
);

remove_timeout;

get_options();

my @files = parse_file_option($file, "args are files");

sub decode ($) {
    my $string = shift;
    chomp $string;
    print unidecode("$string\n");
}

if(@files){
    foreach my $file (@files){
        my $fh = open_file $file;
        while(<$fh>){ decode($_) }
    }
} else {
    while(<STDIN>){ decode($_) }
}
