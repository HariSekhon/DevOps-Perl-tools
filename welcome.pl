#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2009-12-10 17:57:49 +0000 (Thu, 10 Dec 2009)
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

$DESCRIPTION = "Prints a slick welcome message with last login time

Tested on Mac OS X and Linux";

$VERSION = "2.1.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Time::HiRes 'sleep';

autoflush();

my $quick;

%options = (
    "q|quick" => [ \$quick, "Print instantly without fancy scrolling effect, saves 2-3 seconds (you can also Control-C to make output complete instantly)" ],
);
get_options();

set_timeout(20);

# not set on Alpine Linux in Docker
my $user = $ENV{"USER"};
unless($user){
    vlog2 "\$USER not populated, trying whoami";
    $user = `whoami`;
}
unless($user){
    vlog2 "whoami failed, trying 'id' command";
    $user = `id`;
    $user =~ s/.*?\(([^\)]+?)\).*/$1/;
}
unless($user){
    vlog2 "couldn't determine username, falling back to generic user salutation";
    $user = "user";
}
$user = isUser(trim($user)) || die "invalid user '$user' determined from environment variable \$USER\n";
if($user eq "root"){
    $user = uc $user;
} elsif(length($user) < 4 or $user =~ /\d/ or $user eq "user"){
    # probably not a person's name, don't capitalize
} else {
    $user = ucfirst lc $user;
}
my $last_login;
if(which("last", 0)){
    my @output = cmd("last -100", 1);
    for(my $i=1; $i < $#output; $i++){
        $output[$i] =~ /^(?:reboot|wtmp)|^\s*$/ and next;
        $last_login = $output[$i];
        last;
    }
} else {
    print STDERR "WARNING: 'last' command not found, will not be able to get last login information\n";
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
    $msg .= "last login was ";
    if($last_user eq "ROOT"){
        $msg .= "ROOT";
    } elsif(lc $last_user eq lc $user){
        $msg .= "by you";
    } else {
        $msg .= "by $last_user";
    }
    $msg .= " => $last_login";
} else {
    $msg .= "no last login information available!";
}
my $ESC = "\033";
print "${ESC}[s";
$SIG{'INT'} = sub { print "${ESC}[u$msg\n"; exit 1; };

if($quick){
    print "$msg\n";
    exit 0;
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
