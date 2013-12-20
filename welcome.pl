#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2009-12-10 17:57:49 +0000 (Thu, 10 Dec 2009)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Prints a slick welcome message with last login time

Tested on Mac OS X and Linux";

$VERSION = "1.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Time::HiRes 'sleep';

$| = 1;

get_options();

set_timeout();

my $user = $ENV{"USER"} || "user";
$user = isUser($user) || die "invalid user '$user' determined from environment variable \$USER\n";
if($user eq "root"){
    $user = uc $user;
} elsif(length($user) < 4 or $user =~ /\d/){
    # probably not a person's name, don't capitalize
} else {
    $user = ucfirst lc $user;
}
my @output = cmd("last -100");
my $last_login;
for(my $i=1; $i < $#output; $i++){
    $output[$i] =~ /^(?:reboot|wtmp)|^\s*$/ and next;
    $last_login = $output[$i];
    last;
}
my $msg = "Welcome $user - ";
if($last_login){
    ( my $last_user = $last_login ) =~ s/\s+.*$//;
    $last_user = isUser($last_user) || die "invalid user '$last_user' determined from last log";
    $last_user = uc $last_user if $last_user eq "root";
    # strip up to "Day Mon NN" ie "%a %b %e ..."
    $last_login =~ s/.*(\w{3}\s+\w{3}\s+\d+)/$1/ or die "failed to find the date format in the last log";
    $last_login =~ s/ *$//;
    $last_login =~ /^[\w\s\:\(\)-]+$/ or die "last login '$last_login' failed to match expected format";
    $msg .= "last access was by ";
    if($last_user eq $user){
        $msg .= "you";
    } else {
        $msg .= "$last_user";
    }
    $msg .= " => $last_login";
} else {
    $msg .= "no last login information available!";
}

my @charmap = ("A".."Z", "a".."z", 0..9, split('', '@#$%^&*()'));

my $random_char;
foreach my $char (split("", $msg)) {
    print " ";
    my $j = 0;
    while(1){
        if ($j > 3) {
            $random_char = $char;
        } else {
            $random_char = $charmap[int(rand(@charmap))];
        }
        print "\b$random_char";
        last if ("$random_char" eq "$char");
        $j += 1;
        sleep 0.0085;
    }
}
print "\n";
