#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-12-19 18:21:24 +0000 (Thu, 19 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Prints a cool Matrix effect in your terminal

Thanks to my colleagues Chris Greatbanks and Sameer Charania at BSkyB for sharing this cool web tip with me on which I decided to base this code:

http://www.climagic.org/coolstuff/matrix-effect.html";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Time::HiRes 'sleep';
use Term::ReadKey 'GetTerminalSize';

# Original Shell Trick:
#
# echo -e "\e[1;40m" ; clear ; while :; do echo $LINES $COLUMNS $(( $RANDOM % $COLUMNS)) $(( $RANDOM % 72 )) ;sleep 0.05; done|gawk '{ letters="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&*()"; c=$4; letter=substr(letters,c,1);a[$3]=0;for (x in a) {o=a[x];a[x]=a[x]+1; printf "\033[%s;%sH\033[2;32m%s",o,x,letter; printf "\033[%s;%sH\033[1;37m%s\033[0;0H",a[x],x,letter;if (a[x] >= $1) { a[x]=0; } }}'
#
# More clearly:
#
# echo -e "\e[1;40m";
# clear; 
# while :; do
#     echo $LINES $COLUMNS $(( $RANDOM % $COLUMNS)) $(( $RANDOM % 72 )) ;sleep 0.05; done |
#     gawk '{
#         letters="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%^&*()";
#         c=$4;
#         letter=substr(letters,c,1);
#         a[$3]=0;
#         for (x in a) {
#             o=a[x];
#             a[x]=a[x]+1; 
#             printf "\033[%s;%sH\033[2;32m%s",o,x,letter; 
#             printf "\033[%s;%sH\033[1;37m%s\033[0;0H",a[x],x,letter;
#             if(a[x] >= $1){
#                 a[x]=0;
#             }
#         }
#     }'

# Perl Reimplementation, much more readable with explanation comments:

get_options();
my ($columns, $lines, $wpixels, $hpixels) = GetTerminalSize();

$columns = validate_int($columns, 'Terminal columns', 0, 1000);
$lines   = validate_int($lines,   'Terminal lines',   0, 5000);

my @chars = ("A".."Z", "a".."z", 0..9, split('', '@#$%^&*()'));

my $ESC = "\033";

my $system_failure = "  ==> SYSTEM FAILURE <==  ";

autoflush();

set_timeout($timeout, sub { printf "${ESC}[%s;%sH${ESC}[0;40m${ESC}[1;37m%s${ESC}[$lines;${columns}H", int($lines / 2.0) , int($columns / 2.0 - (length($system_failure) / 2.0)), $system_failure; exit 0; } );

# sets terminal to bold black - done per printf
#print "${ESC}[1;40m";
# clear screen     # cursor position to 0,0
print "${ESC}[2J"; # ${ESC}[0;0H";
my (%a, $letter, $line, $column);
while(1){
    $letter = $chars[rand @chars];
    $a{int(rand $columns)} = 0;
    foreach $column (keys %a){
        $line = $a{$column};
        $a{$column} += 1;
        # ESC cursor position to $line, $column
        # ESC bold;black  bg (1;40)
        # ESC faint;green fg (2;32)
        # ESC print $letter
        printf "${ESC}[%s;%sH${ESC}[1;40m${ESC}[2;32m%s", $line, $column, $letter;
        # ESC cursor position line $a{$column}, column $column
        # ESC normal;black bg (0;40) - to not dim white fg chars, allow them to stand out more
        # ESC bold;white   fg (1;37)
        # print $letter
        printf "${ESC}[%s;%sH${ESC}[0;40m${ESC}[1;37m%s",  $a{$column}, $column, $letter;
        # reset to 0,0 coordinates
        #printf "${ESC}[0;0H";
        if($a{$column} >= $lines){
            $a{$column} = 0;
        }
    }
    sleep 0.0565;
}
