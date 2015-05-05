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

$DESCRIPTION = "Scrub usernames/passwords, IP addresses, hostnames, Company Name, Your Name(!) from text logs or config files to make suitable for sharing in email with vendors, public tickets/jiras or pastebin like websites.

Also has support for network device configurations including Cisco and Juniper, and should work on devices with similar configs as well.

Works like a standard unix filter program, taking input from standard input or file(s) given as arguments and prints the modified output to standard output (to redirect to a new file or copy buffer).

Create a list of phrases to scrub from config by placing them in scrub_custom.txt in the same directory as this program, one PCRE format regex per line, blank lines and lines prefixed with # are ignored";

$VERSION = "0.6.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw /:DEFAULT :regex/;

my $file;

my $all       = 0;
my $ip        = 0;
my $ip_prefix = 0;
my $host      = 0;
my $hostname  = 0;
my $domain    = 0;
my $fqdn      = 0;
my $network   = 0;
my $cisco     = 0;
my $screenos  = 0;
my $junos     = 0;
my $custom    = 0;
my $cr        = 0;
my $skip_java_exceptions = 0;

%options = (
    "f|files=s"     => [ \$file,        "File(s) to scrub, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
    "a|all"         => [ \$all,         "Apply all scrubbings (careful this includes --host which can be overzealous and match too many things, in which case try more targeted scrubbings below)" ],
    "i|ip"          => [ \$ip,          "Apply IPv4 IP address and Mac address format scrubbing. This and --ip-prefix below can end up matching version numbers, in which case you can switch to putting your network prefix regex in scrub_custom.conf and using just --custom instead" ],
    "ip-prefix"     => [ \$ip_prefix,   "Apply IPv4 IP address prefix scrubbing but leave last octet (for cluster debugging), still applies full Mac address format scrubbing" ],
    "H|host"        => [ \$host,        "Apply host, domain and fqdn format scrubbing (same as -odF). This will unfortunately scrub Java stack traces of class names also, in which case you can either try --skip-java-exceptions or avoid not use --domain/--fqdn (or --host/--all which includes them), and instead use --custom and put your host/domain regex in scrub_custom.conf" ],
    "o|hostname"    => [ \$hostname,    "Apply hostname format scrubbing (only works on \"<host>:<port>\" otherwise this would match everything (consider using --custom and putting your hostname convention regex in scrub_custom.conf to catch other shortname references)" ],
    "d|domain"      => [ \$domain,      "Apply domain format scrubbing" ],
    "F|fqdn"        => [ \$fqdn,        "Apply fqdn format scrubbing" ],
    "n|network"     => [ \$network,     "Apply all network scrubbing, whether Cisco, ScreenOS, JunOS for secrets, auth, usernames, passwords, md5s, PSKs, AS, SNMP etc." ],
    "c|cisco"       => [ \$cisco,       "Apply Cisco IOS/IOS-XR/NX-OS configuration format scrubbing" ],
    "s|screenos"    => [ \$screenos,    "Apply Juniper ScreenOS configuration format scrubbing" ],
    "j|junos"       => [ \$junos,       "Apply Juniper JunOS configuration format scrubbing (limited, please raise a ticket for extra matches to be added)" ],
    "m|custom"      => [ \$custom,      "Apply custom phrase scrubbing (add your Name, Company Name etc to the list of blacklisted words/phrases one per line in scrub_custom.txt). Matching is case insensitive. Recommended to use to work around --host matching too many things" ],
    "r|cr"          => [ \$cr,          "Strip carriage returns ('\\r') from end of lines leaving only newlines ('\\n')" ],
    "e|skip-java-exceptions" => [ \$skip_java_exceptions,  "Skip lines with Java Exceptions from overly generic domain/fqdn scrubbing to prevent scrubbing java classes needed for debugging stack traces. This is slightly risky as it may potentially miss hostnames/fqdns if colocated on the same lines. Should populate scrub_custom.conf with your domain to remove those instances. After tighter improvements around TLD matching only IANA tlds this should be less needed now" ],
);

@usage_order = qw/files all ip ip-prefix host hostname domain fqdn network cisco screenos junos custom cr skip-java-exceptions/;
get_options();
if($all){
    $ip       = 1;
    $host     = 1;
    $network  = 1;
    $custom   = 1;
}
unless(
    $cisco +
    $custom +
    $domain +
    $fqdn +
    $host +
    $hostname +
    $ip +
    $ip_prefix +
    $network +
    $screenos +
    $junos
    > 0){
    usage "must specify one or more scrubbing types to apply";
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
    $string = scrub_fqdn    ($string)  if $fqdn     and not $host;
    $string = scrub_domain  ($string)  if $domain   and not $host;
    $string = scrub_hostname($string)  if $hostname and not $host;
    $string = scrub_custom  ($string)  if $custom;
    $string = scrub_network ($string)  if $network;
    $string = scrub_cisco   ($string)  if $cisco;
    $string = scrub_screenos($string)  if $screenos;
    $string = scrub_junos($string)     if $junos;
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

##############################
# this host based scrubbings will still scrub class names in random debug messages that I can't predict, and there is always risk of not scrubbing sensitive hosts
#### This is imperfect and a little risky stopping it interfering with Java stack traces this way because it effectively excludes the whole line which may potentially miss legitimiate host regex matches later in the line, will have to watch this

sub skip_java_exceptions($$;$){
    my $string = shift;
    my $regex  = shift;
    my $name   = shift || "";
    $name = " $name";
    if($skip_java_exceptions){
        if($string =~ /(?:^\s+at|^Caused by:)\s+\w+(?:\.\w+)+/){
            debug "skipping$name \\s+at|^Caused by";
            return 1;
        }
        if($string =~ /\($regex:[\w-]+\(\d+\)\)/){
            debug "skipping$name (regex):\\w(\\d+)";
            return 1;
        }
        if($string =~ /^(?:\w+\.)*\w+Exception:/){
            debug "skipping$name (?:\\w+\\.)*\\w+Exception:";
            return 1;
        }
        if($string =~ /\$\w+\($regex:\d+\)/){
            debug "skipping$name \$\\w+(regex)";
            return 1;
        }
    }
    return 0;
}

sub scrub_hostname($){
    my $string = shift;
    return $string if skip_java_exceptions($string, $hostname_regex, "hostname");
    $string =~ s/$hostname_regex(!<\.java):(\d{1,5}(?:[^A-Za-z]|$))/<host>:$1/go;
    return $string;
}

sub scrub_domain($){
    my $string = shift;
    return $string if skip_java_exceptions($string, $domain_regex2, "domain");
    $string =~ s/$domain_regex2/<domain>/go;
    return $string;
}

sub scrub_fqdn($){
    my $string = shift;
    return $string if skip_java_exceptions($string, $fqdn_regex, "fqdn");
    # variable length lookbehind is not implemented, so can't use full $tld_regex (which might be too permissive anyway)
    $string =~ s/$fqdn_regex/<fqdn>/go;
    return $string;
}

sub scrub_host($){
    my $string = shift;
    $string = scrub_fqdn($string);
    $string = scrub_domain($string);
    $string = scrub_hostname($string);
    return $string;
}
##############################

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
    $string =~ s/username .*/username <username>/;
    $string =~ s/syscontact .*/syscontact <syscontact>/;
    return $string;
}

sub scrub_cisco($){
    my $string = shift;
    $string =~ s/username .+ (?:password|secret) .*?$/username <username> password <password>/g;
    $string =~ s/password .*?$/password <password>/g;
    $string =~ s/secret .*?$/secret <secret>/g;
    $string =~ s/\smd5\s+.*?$/ md5 <md5>/g;
    $string =~ s/\scommunity\s+.*$/ community <community>/g;
    $string =~ s/(standby\s+\d+\s+authentication).*/$1 <auth>/g;
    $string =~ s/\sremote-as\s\d+/remote-as <AS>/g;
    $string =~ s/\sdescription\s.*$/description <description>/g;
    $string = scrub_network_generic($string) unless $network;
    return $string;
}

sub scrub_screenos($){
    my $string = shift;
    $string =~ s/set admin (name|user|password) "?.+"?/set admin $1 <scrubbed>/g;
    $string =~ s/set snmp (community|host) "?.+"?/set snmp $1 <scrubbed>/g;
    $string =~ s/ md5 "?.+"?/ md5 <md5>/g;
    $string =~ s/ key [^\s]+ (?:!enable)/ key <key>/g;
    $string =~ s/set nsmgmt init id [^\s]+/set nsmgmt init id <id>/g;
    $string =~ s/preshare .+? /preshare <psk> /g;
    $string = scrub_network_generic($string) unless $network;
    return $string;
}

sub scrub_junos($){
    my $string = shift;
    $string =~ s/pre-shared-key\s.*/pre-shared-key <psk>/g;
    $string =~ s/\shome\s+.*/ home <home>/g;
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
