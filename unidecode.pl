#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2012-04-06 21:01:42 +0100 (Fri, 06 Apr 2012)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION="Convert UTF to ASCII, works as a standard unix filter program";
$VERSION = "0.6";

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
my @files;

%options = (
    "f|file=s"      => [ \$file, "File to unidecode" ],
);

get_options();;

if($file){
    my @tmp = split(/\s*,\s*/, $file);
    push(@files, @tmp);
}

foreach(@ARGV){
    push(@files, $_);
}

( $file and not -f $file ) and die "Error: couldn't find file '$file'\n";
foreach my $file (@files){
    if(not -f $file ){
        print STDERR "File not found: '$file'\n";
        @files = grep { $_ ne $file } @files;
    }
}

vlog_options "files", "[ '" . join("', '", @files) . "' ]";

if(@files){
    foreach my $file (@files){
        open(my $fh, $file) or die "Failed to open file '$file': $!\n";
        while(<$fh>){ decode($_) }
    }
} else {
    while(<STDIN>){ decode($_) }
}

sub decode {
    my $string = shift;
    chomp $string;
    print unidecode("$string\n");
}
