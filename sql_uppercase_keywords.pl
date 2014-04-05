#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-06-05 14:08:20 +0100 (Wed, 05 Jun 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

my $CONF     = "sql_keywords.conf";
my $PIG_CONF = "pig_keywords.conf";

our $DESCRIPTION = "Util to uppercase SQL-like keywords from stdin or file(s), prints to standard output

Primarily written to help me clean up various SQL across Hive / Impala / MySQL / Cassandra CQL etc.

Uses a regex list of keywords located in the same directory as this program
called $CONF for easy maintainance and addition of keywords";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $file;
my $comments;

%options = (
    "f|files=s"      => [ \$file,       "File(s) to uppercase SQL from. Non-option arguments are added to the list of files" ],
    "c|comments"     => [ \$comments,   "Apply transformations even to lines that are commented out using -- or #" ],
);
@usage_order = qw/files comments/;

if($progname eq "pig_uppercase_keywords.pl"){
    $CONF = $PIG_CONF;
    $DESCRIPTION =~ s/various SQL.*/Pig code and documentation/;
    $DESCRIPTION =~ s/SQL-like/Pig/;
    @{$options{"f|files=s"}}[1] =~ s/SQL/Pig Latin/;
}

get_options();

my @files = parse_file_option($file, "args are files");
my %sql_keywords;
my $comment_chars = qr/(?:^|\s)(?:#|--)/;

my $fh = open_file dirname(__FILE__) . "/$CONF";
foreach(<$fh>){
    chomp;
    s/(?:#|--).*//;
    /^\s*$/ and next;
    $_ = trim($_);
    my $sql = $_;
    $sql =~ s/\s+/\\s+/g;
    # protection against ppl leaving matching brackets in sql_keywords.txt
    $sql =~ s/([^\\])\(([^\?])/$1\(?:$2/g;
    # wraps regex in (?:XISM: )
    #$sql = validate_regex($sql);
    $sql_keywords{$sql} = uc $_;
}

sub uppercase_sql ($) {
    my $string            = shift;
    my $captured_comments = undef;
    #$string =~ /(?:SELECT|SHOW|ALTER|DROP|TRUNCATE|GRANT|FLUSH)/ or return $string;
    unless($comments){
        if($string =~ s/(${comment_chars}.*$)//){
            $captured_comments = $1;
        }
    }
    if($string){
        # cannot simply use word boundary here since NULL would match /dev/null
        my $sep = '\s|\(|\)|\[|\]|,|\.\.\.|;|\n|\r\n|\"|' . "'";
        foreach my $sql (sort keys %sql_keywords){
            if($string =~ /($sep)?($sql)($sep|$)/gi){
                my $uc_sql = uc $2;
                # have to redefine comment chars here because variable length negative lookbehind isn't implemented
                $string =~ s/(?<!\s#)(?<!\s--)(^|$sep)$sql($sep|$)/$1$uc_sql$2/gi;
            }
        }
    }
    if($captured_comments){
        chomp $string;
        $string .= $captured_comments . "\n";
    }
    return $string;
}

if(@files){
    foreach my $file (@files){
        open(my $fh, $file) or die "Failed to open file '$file': $!\n";
        while(<$fh>){ print uppercase_sql($_) }
    }
} else {
    while(<STDIN>){ print uppercase_sql($_) }
}
