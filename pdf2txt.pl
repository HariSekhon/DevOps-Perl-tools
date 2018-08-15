#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-02-01 16:22:00 +0000 (Fri, 01 Feb 2013)
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

$DESCRIPTION="Tool for converting PDF to text for text analytics. Rustled this up quickly in Cloudera to analyze our internal KB for an unofficial topic challenge, which I won as a result of using this and a Java MapReduce word count :)

Operates as a standard unix filter program taking any number of PDF files as arguments (or -f/--pdf comma separated files or PDF content in standard input) and outputting the text to standard output.

See also Apache PDFBox and pdf2text unix tool";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use CAM::PDF;
use CAM::PDF::PageText;

$github_repo = "tools";

my $filename;

%options = (
    "f|pdf=s" =>  [ \$filename, "PDF File to extract TXT from" ],
);

get_options();
my @filenames = split(/,/, $filename) if $filename;
push(@filenames, @ARGV);
push(@filenames, "-") unless @filenames;

my $pdf;
foreach(@filenames){
    if($_ eq "-"){
        print "PDF STDIN:\n";
    } else {
        print "PDF filename: $_";
    }
    $pdf = CAM::PDF->new($_);
#my $pageone_tree = $pdf->getPageContentTree(4);
#print CAM::PDF::PageText->render($pageone_tree);
    unless($pdf){
        print "No valid PDF detected, skipping...\n";
        next;
    }
    foreach(1..$pdf->numPages()){
        # TODO: this doesn't really work well, tried getPageContent which works even less well...
        print "page $_: " . $pdf->getPageText($_) . "\n";
    }
}
