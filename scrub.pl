#!/usr/bin/perl -T
#
#  Author:       Hari Sekhon
#  Date:         2010-05-18 10:39:51 +0100 (Tue, 18 May 2010)
#  Rewrite Date: 2013-07-18 21:17:41 +0100 (Thu, 18 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

# TODO: split out Cisco + ScreenOS matches to files for easy maintenance/extension;

$DESCRIPTION = "Scrub username/passwords, IP addresses, hostnames, Company Name, Your Name(!) from text logs or config files to make suitable for sharing in email or pastebin like websites.

Works like a standard unix filter program, taking input from standard input or file(s) given as arguments and prints the modified output to standard output.

Create a list of phrases to scrub from config by placing them in scrub_custom.txt in the same directory as this program, one PCRE format regex per line, blank lines and lines prefixed with # are ignored

Early stage rewrite + unification of a few scripts I wrote for personal use years ago when I was more of a sysadmin/netadmin";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw /:DEFAULT :regex/;

my $file;

my $all      = 0;
my $ip       = 0;
my $host     = 0;
my $network  = 0;
my $cisco    = 0;
my $screenos = 0;
my $custom   = 0;

%options = (
    "f|files=s"     => [ \$file,        "File(s) to scrub, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
    "a|all"         => [ \$all,         "Apply all scrubbings (Recommended)" ],
    "i|ip"          => [ \$ip,          "Apply IPv4 IP address and Mac address format scrubbing" ],
    #"H|host"        => [ \$host,        "Apply domain and fqdn format scrubbing (custom TLDs will not be caught by this)" ],
    "n|network"     => [ \$network,     "Apply all network scrubbing, whether Cisco, ScreenOS, JunOS ..." ],
    "c|cisco"       => [ \$cisco,       "Apply Cisco IOS/IOS-XR/NX-OS configuration format scrubbing" ],
    "s|screenos"    => [ \$screenos,    "Apply Juniper ScreenOS configuration format scrubbing" ],
    "m|custom"      => [ \$custom,      "Apply custom phrase scrubbing (add your Name, Company Name etc to the list of blacklisted words/phrases one per line in scrub_custom.txt). Matching is case insensitive" ],
);

@usage_order = qw/files all ip host network cisco screenos custom/;
get_options();
if($all){
    $ip       = 1;
    $host     = 1;
    $network  = 1;
    $custom   = 1;
}
unless($ip + $host + $network + $cisco + $screenos + $custom > 1){
    usage "must specify a scrubbing to apply";
}

my @files = parse_file_option($file, "args are files");

my @custom_phrases;
if($custom){
    my $scrub_custom_txt = dirname(__FILE__) . "/scrub_custom.txt";
    my $fh;
    if(open $fh, $scrub_custom_txt){
        while(<$fh>){
            chomp;
            s/#.*//;
            next if /^\s*$/;
            push(@custom_phrases, $_);
        }
        @custom_phrases or die "Failed to read any custom phrases from '$scrub_custom_txt'\n";
        close $fh;
    } else {
        warn "warning: failed to open file $scrub_custom_txt, continuing without...\n";
    }
}

sub scrub($){
    my $string = shift;
    $string =~ /(\r?\n)$/;
    my $line_ending = $1;
    chomp $string;
    $string = scrub_ip      ($string)  if $ip;
    $string = scrub_host    ($string)  if $host;
    $string = scrub_custom  ($string)  if $custom;
    $string = scrub_network ($string)  if $network;
    $string = scrub_cisco   ($string)  if $cisco;
    $string = scrub_screenos($string)  if $screenos;
    return "$string$line_ending";
}

sub scrub_custom($){
    my $string = shift;
    my $phrase_regex = "";
    foreach(@custom_phrases){
        chomp;
        $phrase_regex .= "$_|";
    }
    $phrase_regex =~ s/\|$//;
    $string =~ s/\b$phrase_regex\b/<custom_phrase>/gio;
    return $string;
}

sub scrub_ip($){
    my $string = shift;
    #$string =~ s/$ip_regex\/\d+/<ip>\/<cidr>/go;
    #$string =~ s/$subnet_mask_regex\/\d+/<subnet>\/<cidr>/go;
    $string =~ s/$ip_regex/<ip>/go;
    $string =~ s/$subnet_mask_regex/<subnet>/go;
    $string =~ s/$mac_regex/<mac>/g;
    # network device format Mac address
    $string =~ s/\b(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}\b/<mac>/g;
    return $string;
}

sub scrub_host($){
    my $string = shift;
    # This currently matches too much stuff
    #$string =~ s/$fqdn_regex/<fqdn>/go;
    #$string =~ s/$domain_regex/<domain>/go;
    return $string;
}

sub scrub_network($){
    my $string = shift;
    $string = scrub_cisco($string);
    $string = scrub_screenos($string);
    $string = scrub_junos($string);
    $string = scrub_network_generic($string);
    return $string;
}

sub scrub_network_generic($){
    my $string = shift;
    $string =~ s/username .*/username <scrubbed>/;
    $string =~ s/syscontact .*/syscontact <scrubbed>/;
    return $string;
}

sub scrub_cisco($){
    my $string = shift;
    $string =~ s/username .+ (?:password|secret) .*?$/username <scrubbed> password <scrubbed>/g;
    $string =~ s/password .*?$/password <scrubbed>/g;
    $string =~ s/secret .*?$/secret <scrubbed>/g;
    $string =~ s/\smd5\s+.*?$/ md5 <scrubbed>/g;
    $string =~ s/\scommunity\s+.*$/ community <scrubbed>/g;
    $string =~ s/(standby\s+\d+\s+authentication).*/$1 <scrubbed>/g;
    $string =~ s/\sremote-as\s\d+/remote-as <AS>/g;
    $string =~ s/\sdescription\s.*$/description <description>/g;
    $string = scrub_network_generic($string) unless $network;
    return $string;
}

sub scrub_screenos($){
    my $string = shift;
    $string =~ s/set admin (name|user|password) "?.+"?/set admin $1 <scrubbed>/g;
    $string =~ s/set snmp (community|host) "?.+"?/set snmp $1 <scrubbed>/g;
    $string =~ s/ md5 "?.+"?/ md5 <scrubbed>/g;
    $string =~ s/ key [^[:space:]]+ (?:!enable)/ key <scrubbed>/g;
    $string =~ s/set nsmgmt init id [^[:space:]]+/set nsmgmt init id <scrubbed>/g;
    $string =~ s/preshare .+? /preshare <scrubbed> /g;
    $string = scrub_network_generic($string) unless $network;
    return $string;
}

sub scrub_junos($){
    my $string = shift;
    $string =~ s/pre-shared-key\s.*/pre-shared-key <scrubbed>/g;
    $string =~ s/\shome\s+.*/ home <scrubbed>/g;
    $string = scrub_network_generic($string) unless $network;
    return $string;
}

# ============================================================================ #
# main()
if(@files){
    foreach my $file (@files){
        open(my $fh, $file) or die "Failed to open file '$file': $!\n";
        while(<$fh>){ print scrub($_) }
    }
} else {
    while(<STDIN>){ print scrub($_) }
}
