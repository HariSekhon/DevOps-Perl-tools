#!/usr/bin/perl -T
#
#  Author:       Hari Sekhon
#  Date:         2010-05-18 10:39:51 +0100 (Tue, 18 May 2010)
#  Rewrite Date: 2013-07-18 21:17:41 +0100 (Thu, 18 Jul 2013)
#
#  http://github.com/harisekhon/toolbox
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Scrub username/passwords, IP addresses, hostnames, Company Name, Your Name(!) from text logs or config files to make suitable for sharing in email with vendors, public tickets/jiras or pastebin like websites.

Works like a standard unix filter program, taking input from standard input or file(s) given as arguments and prints the modified output to standard output (to redirect to a new file or copy buffer).

Create a list of phrases to scrub from config by placing them in scrub_custom.txt in the same directory as this program, one PCRE format regex per line, blank lines and lines prefixed with # are ignored";

$VERSION = "0.5.2";

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
my $ip_prefix = 0;
my $host     = 0;
my $network  = 0;
my $cisco    = 0;
my $screenos = 0;
my $custom   = 0;
my $cr       = 0;
my $skip_java_exceptions = 0;

%options = (
    "f|files=s"     => [ \$file,        "File(s) to scrub, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
    "a|all"         => [ \$all,         "Apply all scrubbings (careful this includes --host which can be overzealous and match too many things)" ],
    "i|ip"          => [ \$ip,          "Apply IPv4 IP address and Mac address format scrubbing. This and --ip-prefix below can end up matching version numbers, in which case you can switch to putting your network prefix regex in scrub_custom.conf and using just --custom instead" ],
    "ip-prefix"     => [ \$ip_prefix,   "Apply IPv4 IP address prefix scrubbing but leave last octet (for cluster debugging), still applies full Mac address format scrubbing" ],
    "H|host"        => [ \$host,        "Apply host, domain and fqdn format scrubbing. This will unfortunately scrub Java stack traces of class names also, in which case you should not use --host or --all, instead use --custom and put your domain regex in scrub_custom.conf" ],
    "n|network"     => [ \$network,     "Apply all network scrubbing, whether Cisco, ScreenOS, JunOS ..." ],
    "c|cisco"       => [ \$cisco,       "Apply Cisco IOS/IOS-XR/NX-OS configuration format scrubbing" ],
    "s|screenos"    => [ \$screenos,    "Apply Juniper ScreenOS configuration format scrubbing" ],
    "m|custom"      => [ \$custom,      "Apply custom phrase scrubbing (add your Name, Company Name etc to the list of blacklisted words/phrases one per line in scrub_custom.txt). Matching is case insensitive. Recommended to use to work around --host matching too many things" ],
    "r|cr"          => [ \$cr,          "Strip carriage returns ('\\r') from end of lines leaving only newlines ('\\n')" ],
    "e|skip-java-exceptions" => [ \$skip_java_exceptions,  "Skip lines with Java Exceptions from host/fqdn scrubbing to prevent scrubbing java classes needed for debugging stack traces. This is slightly risky as it may potentially miss hostnames/fqdns if colocated on the same lines" ],
);

@usage_order = qw/files all ip ip-prefix host network cisco screenos custom cr skip-java-exceptions/;
get_options();
if($all){
    $ip       = 1;
    $host     = 1;
    $network  = 1;
    $custom   = 1;
}
unless($ip + $ip_prefix + $host + $network + $cisco + $screenos + $custom > 0){
    usage "must specify a scrubbing to apply";
}
($ip and $ip_prefix) and usage "cannot specify both --ip and --ip-prefix, they are mutually exclusive behaviours";

my @files = parse_file_option($file, "args are files");

my @custom_phrases;
if($custom){
    my $scrub_custom_txt = dirname(__FILE__) . "/scrub_custom.conf";
    my $fh;
    if(open $fh, $scrub_custom_txt){
        while(<$fh>){
            chomp;
            s/#.*//;
            next if /^\s*$/;
            push(@custom_phrases, $_);
        }
        #@custom_phrases or die "Failed to read any custom phrases from '$scrub_custom_txt'\n";
        close $fh;
    } else {
        warn "warning: failed to open file $scrub_custom_txt, continuing without...\n";
    }
}

sub scrub($){
    my $string = shift;
    $string =~ /(\r?\n)$/;
    my $line_ending = $1;
    $line_ending = "\n" if $cr;
    # this doesn't chomp \r, only \n
    #chomp $string;
    $string =~ s/(?:\r?\n)$//;
    $string = scrub_ip_prefix ($string) if $ip_prefix;
    $string = scrub_ip      ($string)  if $ip and not $ip_prefix;
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
        #print "custom_phrase: <$_>\n";
        $phrase_regex .= "$_|";
    }
    $phrase_regex =~ s/\|$//;
    #print "phrase_phrase: <$phrase_regex>\n";
    if($phrase_regex){
        $string =~ s/(\b|_)(?:$phrase_regex)(\b|_)/$1<custom_scrubbed>$2/gio;
        #foreach(@custom_phrases){
        #    chomp;
        #    $string =~ s/(\b|_)$_(\b|_)/$1<custom_scrubbed>$2/gio;
        #}
    }
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

sub scrub_ip_prefix($){
    my $string = shift;
    $string =~ s/$ip_prefix_regex/<ip_prefix>/go;
    $string =~ s/$subnet_mask_regex/<subnet>/go;
    $string =~ s/$mac_regex/<mac>/g;
    # network device format Mac address
    $string =~ s/\b(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}\b/<mac>/g;
    return $string;
}

# TODO: split in to scrub_hostname, scrub_fqdn, scrub_domain
sub scrub_host($){
    my $string = shift;
    # this will still scrub class names in random debug messages that I can't predict, and there is always risk of not scrubbing sensitive hosts
    #### This is imperfect and a little risky stopping it interfering with Java stack traces this way because it effectively excludes the whole line which may potentially miss legitimiate host regex matches later in the line, will have to watch this
    if($skip_java_exceptions){
        return $string if $string =~ /(?:^\s+at|^Caused by:)\s+\w+(?:\.\w+)+/                           and debug "skipping \\sat|^Caused by";
        return $string if $string =~ /\((?:$hostname_regex|$fqdn_regex|$domain_regex2):[\w-]+\(\d+\)\)/ and debug "skipping (regex):\\w(\\d+)";
        # overzealous, strips long hostnames that partial match and the beginning and \.\w+ the rest
        #return $string if $string =~ /^(?:$fqdn_regex)\.\w/                                             and debug "skipping ^regex.\\w+";
        return $string if $string =~ /\$\w+\((?:$hostname_regex|$fqdn_regex|$domain_regex2):\d+\)/      and debug "skipping \$\\w+(regex)";
    }
    $string =~ s/$fqdn_regex/<fqdn>/go;
    ####
    $string =~ s/$hostname_regex:(\d{1,5}(?:[^A-Za-z]|$))/<host>:$1/go;
    # This currently matches too much stuff
    # variable length lookbehind is not implemented, so can't use full $tld_regex (which might be too permissive anyway)
    $string =~ s/$domain_regex2/<domain>/go;
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
    $string =~ s/ key [^\s]+ (?:!enable)/ key <scrubbed>/g;
    $string =~ s/set nsmgmt init id [^\s]+/set nsmgmt init id <scrubbed>/g;
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
