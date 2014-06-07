#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2014-06-07 22:17:09 +0100 (Sat, 07 Jun 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Program to show all the ASCII terminal code Foreground/Background color combinations in a terminal to make it easy to pick for writing fancy programs";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

%options = (
);

get_options();

autoflush();

my $text = "hari";

print "\nASCII Terminal Codes Color Key:\n\n";
print "      BG";
for(my $bg=40; $bg <= 47; $bg++){
    printf " %-9s", "${bg}m";
}
printf "\n%5s\n", "FG";
for(my $fg=29; $fg <= 38; $fg++){
    foreach(my $effect=0; $effect <= 1; $effect++){
        printf "%2s%sm  ", $effect ? "$effect;" : "", $fg;
        for(my $bg=40; $bg <= 47; $bg++){
            printf "\e[$effect;${fg}m\e[${bg}m  $text  \e[0m  ", $fg, $bg;
        }
        print "\n";
    }
}

exit 0;
