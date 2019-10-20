#!/usr/bin/perl -T
#
#  Author:       Hari Sekhon
#  Date:         2010-05-18 10:39:51 +0100 (Tue, 18 May 2010)
#  Rewrite Date: 2013-07-18 21:17:41 +0100 (Thu, 18 Jul 2013)
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

$DESCRIPTION = "Anonymizes usernames, passwords, IP addresses, hostnames, emails addresses, Company Name, Your Name(!) from text logs or config files to make suitable for sharing in email with vendors, public tickets, Jiras or pastebin like websites.

Also has support for network device configurations including Cisco and Juniper, and should work on devices with similar configs as well.

Works like a standard unix filter program, reading from file arguments or standard input and printing the modified output to standard output (to redirect to a new file or copy buffer).

Create a list of phrases to anonymize from config by placing them in anonymize_custom.conf in the same directory as this program, one PCRE format regex per line, blank lines and lines prefixed with # are ignored.

Ignore phrases are in a similar file anonymize_ignore.conf, also adjacent to this program.

There is also a newer Python version with more redactions and features such as --hash-hostnames available at https://github.com/harisekhon/devops-python-tools
";

$VERSION = "0.13.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw /:DEFAULT :regex/;

my $user_name = 'user(?:name)?';
my $arg_sep = '[=\s:]+';
# openssl uses -passin switch
my $pass_word_phrase = 'pass(?:word|phrase|in)?';

my $file;

my $all       = 0;
my $ip        = 0;
my $ip_prefix = 0;
my $host      = 0;
my $hostname  = 0;
my $domain    = 0;
my $fqdn      = 0;
my $email     = 0;
my $http_auth = 0;
my $kerberos  = 0;
my $network   = 0;
my $user      = 0;
my $password  = 0;
my $port      = 0;
my $proxy     = 0;
my $cisco     = 0;
my $screenos  = 0;
my $junos     = 0;
my $custom    = 0;
my $cr        = 0;
my $skip_java_exceptions = 0;
my $skip_python_tracebacks = 0;
my $skip_exceptions = 0;

%options = (
    "f|files=s"     => [ \$file,        "File(s) to anonymize, non-option arguments are also counted as files. If no files are given uses standard input stream" ],
    "a|all"         => [ \$all,         "Apply all anonymizations (careful this includes --host which can be overzealous and match too many things, in which case try more targeted anonymizations below)" ],
    "i|ip"          => [ \$ip,          "Apply IPv4 IP address and Mac address format anonymization. This and --ip-prefix below can end up matching version numbers (eg. \"HDP 2.2.4.2\" => \"HDP <ip>\"), in which case you can switch to putting your network prefix regex in anonymize_custom.conf and using just use --custom instead" ],
    "ip-prefix"     => [ \$ip_prefix,   "Apply IPv4 IP address prefix anonymization but leave last octet to help distinguish nodes for cluster debugging (eg. \"node 172.16.100.51 failed to contact 172.16.100.52\" => \"<ip_prefix>.51 failed to contact <ip_prefix>.52\") , still applies full Mac address format anonymization" ],
    "H|host"        => [ \$host,        "Apply host, domain and fqdn format anonymization (same as -odF). This may anonymize some Java stack traces of class names also, in which case you can either try --skip-java-exceptions or avoid using --domain/--fqdn (or --host/--all which includes them), and instead use --custom and put your host/domain regex in anonymize_custom.conf" ],
    "o|hostname"    => [ \$hostname,    "Apply hostname format anonymization (only works on \"<host>:<port>\" otherwise this would match everything (consider using --custom and putting your hostname convention regex in anonymize_custom.conf to catch other shortname references)" ],
    "d|domain"      => [ \$domain,      "Apply domain format anonymization" ],
    "F|fqdn"        => [ \$fqdn,        "Apply fqdn format anonymization" ],
    "P|port"        => [ \$port,        "Apply port anonymization (not included in --all since you usually want to include port numbers for cluster or service debugging)" ],
    "u|user"        => [ \$user,        "Apply user anonymization (user=<user>). Auto enables --password)" ],
    "p|password"    => [ \$password,    "Apply password anonymization against --password switches (can't catch MySQL -p<password> since it's too ambiguous with bunched arguments, can use --custom to work around). Also covers curl -u user:password" ],
    "T|http-auth"   => [ \$http_auth,   "Apply HTTP auth anonymization to replace http://username:password\@ => http://<user>:<password>\@. Also works with https://" ],
    "k|kerberos"    => [ \$kerberos,    "Kerberos 5 principals in the form <primary>@<realm> or <primary>/<instance>@<realm> (where <realm> must match a valid domain name - otherwise use --custom and populate anonymize_custom.conf). These kerberos principals are anonymized to <kerberos_principal>. There is a special exemption for Hadoop Kerberos principals such as NN/_HOST@<realm> which preserves the literal '_HOST' instance since that's useful to know for debugging, the principal and realm will still be anonymized in those cases (if wanting to retain NN/_HOST then use --domain instead of --kerberos). This is applied before --email in order to not prevent the email replacement leaving this as user/host\@realm to user/<email_regex>, which would have exposed 'user'" ],
    "E|email"       => [ \$email,       "Apply email format anonymization" ],
    "x|proxy"       => [ \$proxy,       "Apply anonymization to remove proxy host, user etc (eg. from curl -iv output). You should probably also apply --ip and --host if using this.Auto enables --http-auth" ],
    "n|network"     => [ \$network,     "Apply all network anonymization, whether Cisco, ScreenOS, JunOS for secrets, auth, usernames, passwords, md5s, PSKs, AS, SNMP etc." ],
    "c|cisco"       => [ \$cisco,       "Apply Cisco IOS/IOS-XR/NX-OS configuration format anonymization" ],
    "s|screenos"    => [ \$screenos,    "Apply Juniper ScreenOS configuration format anonymization" ],
    "j|junos"       => [ \$junos,       "Apply Juniper JunOS configuration format anonymization (limited, please raise a ticket for extra matches to be added)" ],
    "m|custom"      => [ \$custom,      "Apply custom phrase anonymization (add your Name, Company Name etc to the list of blacklisted words/phrases one per line in anonymize_custom.conf). Matching is case insensitive. Recommended to use to work around --host matching too many things" ],
    "r|strip-cr"    => [ \$cr,          "Strip carriage returns ('\\r') from end of lines leaving only newlines ('\\n')" ],
    "skip-java-exceptions"   => [ \$skip_java_exceptions,   "Skip lines with Java Exceptions from generic host/domain/fqdn anonymization to prevent anonymization java classes needed for debugging stack traces. This is slightly risky as it may potentially miss hostnames/fqdns if colocated on the same lines. Should populate anonymize_custom.conf with your domain to remove those instances. After tighter improvements around matching only IANA TLDs this should be less needed now" ],
    "skip-python-tracebacks" => [ \$skip_python_tracebacks, "Skip lines with Python Tracebacks, similar to --skip-java-exceptions" ],
    "e|skip-exceptions"      => [ \$skip_exceptions,        "Skip both Java exceptions and Python tracebacks (recommended)" ],
);
remove_timeout();

@usage_order = qw/files all ip ip-prefix host hostname domain fqdn port password kerberos email proxy network cisco screenos junos custom cr skip-java-exceptions skip-python-tracebacks skip-exceptions/;
get_options();
if($all){
    $ip        = 1;
    $host      = 1;
    $email     = 1;
    $http_auth = 1;
    $kerberos  = 1;
    $network   = 1;
    $user      = 1;
    $password  = 1;
    $proxy     = 1;
    $custom    = 1;
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
    $email +
    $kerberos +
    $network +
    $user +
    $password +
    $port +
    $proxy +
    $screenos +
    $junos
    > 0){
    usage "must specify one or more anonymization types to apply";
}
($ip and $ip_prefix) and usage "cannot specify both --ip and --ip-prefix, they are mutually exclusive behaviours";
if($skip_exceptions){
    $skip_python_tracebacks = 1;
    $skip_java_exceptions   = 1;
}
if($user){
    $password = 1;
}

my @files = parse_file_option($file, "args are files");

my @custom_phrases;
if($custom){
    my $anonymize_custom_conf = dirname(__FILE__) . "/anonymize_custom.conf";
    my $fh;
    if(open $fh, $anonymize_custom_conf){
        while(<$fh>){
            chomp;
            s/#.*//;
            next if /^\s*$/;
            push(@custom_phrases, $_);
        }
        #@custom_phrases or warn "Failed to read any custom phrases from '$anonymize_custom_conf'\n";
        close $fh;
    } else {
        warn "warning: failed to open file $anonymize_custom_conf, continuing without...\n";
    }
}

my $anonymize_ignore_conf = dirname(__FILE__) . "/anonymize_ignore.conf";
my $fh;
my $ignore_regex;
if(open $fh, $anonymize_ignore_conf){
    while(<$fh>){
        chomp;
        s/#.*//;
        next if /^\s*$/;
        isRegex($_) or die "Invalid regex detected in $anonymize_ignore_conf: $_\n";
        $ignore_regex .= "$_|";
    }
    close $fh;
    if(defined($ignore_regex)){
        $ignore_regex =~ s/\|$//;
        $ignore_regex =~ /^\s*$/ and code_error "Invalid ignore regex, cannot be blank!";
        $ignore_regex = qr/$ignore_regex/o;
        vlog3 "ignore regex: $ignore_regex";
    } else {
        warn "Failed to read any regex to ignore from '$anonymize_ignore_conf'\n";
    }
} else {
    warn "warning: failed to open file $anonymize_ignore_conf, continuing without...\n";
}

sub anonymize($){
    my $string = shift;
    $string =~ /(\r?\n)$/;
    my $line_ending = $1;
    $line_ending = "" unless ($line_ending);
    $line_ending = "\n" if $cr;
    # this doesn't chomp \r, only \n
    #chomp $string;
    $string =~ s/(?:\r?\n)$//;
    #return "$string$line_ending" if anonymize_ignore($string);
    $string = anonymize_ip_prefix   ($string)  if $ip_prefix;
    $string = anonymize_ip          ($string)  if $ip and not $ip_prefix;
    $string = anonymize_kerberos    ($string)  if $kerberos; # must be done before anonymize_email and anonymize_host in order to match, otherwise anonymize_email will leave user@<email_regex>
    $string = anonymize_email       ($string)  if $email;    # must be done before anonymize_host in order to match
    $string = anonymize_host        ($string)  if $host;
    $string = anonymize_fqdn        ($string)  if $fqdn     and not $host;
    $string = anonymize_domain      ($string)  if $domain   and not $host;
    $string = anonymize_hostname    ($string)  if $hostname and not $host;
    $string = anonymize_user        ($string)  if $user;
    $string = anonymize_password    ($string)  if $password;
    $string = anonymize_port        ($string)  if $port;
    $string = anonymize_http_auth   ($string)  if $http_auth;
    $string = anonymize_proxy       ($string)  if $proxy;
    $string = anonymize_network     ($string)  if $network;
    $string = anonymize_cisco       ($string)  if $cisco;
    $string = anonymize_screenos    ($string)  if $screenos;
    $string = anonymize_junos       ($string)  if $junos;
    $string = anonymize_custom      ($string)  if $custom;
    return "$string$line_ending";
}

sub anonymize_custom($){
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
        $string =~ s/(\b|[^A-Za-z])(?:$phrase_regex)(\b|[^A-Za-z])/$1<custom>$2/gio;
        #foreach(@custom_phrases){
        #    chomp;
        #    $string =~ s/(\b|_)$_(\b|_)/$1<custom_anonymized>$2/gio;
        #}
    }
    return $string;
}

# This used to do one ignore per line, but that is much too inflexible as we may want to ignore part of a line but not the whole line
#sub anonymize_ignore($){
#    my $string = shift;
#    my $phrase_regex = "";
#    foreach(@ignore_lines){
#        chomp;
#        #print "ignore_phrase: <$_>\n";
#        $phrase_regex .= "$_|";
#    }
#    $phrase_regex =~ s/\|$//;
#    #print "phrase_phrase: <$phrase_regex>\n";
#    if($phrase_regex){
#        return 1 if $string =~ /$phrase_regex/;
#    }
#    return 0;
#}

sub anonymize_mac($){
    my $string = shift;
    $string =~ s/$mac_regex/<mac>/g;
    # network device format Mac address
    $string =~ s/\b(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}\b/<mac>/g;
    return $string;
}

sub anonymize_ip($){
    my $string = shift;
    # leave cidr mask for debugging clusters
    #$string =~ s/$ip_regex\/\d+/<ip>\/<cidr>/go;
    #$string =~ s/$subnet_mask_regex\/\d+/<subnet>\/<cidr>/go;

    # unfortunately this anonymizes /usr/hdp/2.3.0.0-2557 => /usr/hdp/<ip>-2557
    #$string =~ s/$ip_regex/<ip>/go;
    # make sure it's not part of a bigger numeric string like a version number, but still catch ip:port
    $string =~ s/(?<!\d\.)$ip_regex(?![^:]\d+)/<ip_x.x.x.x>/go;

    # this will never match now that $ip_regex permits ending in 0 for cidr
    $string =~ s/(?<!\d\.)$subnet_mask_regex(?!\.\d+)(?!-\d+)/<subnet_x.x.x.x>/go;

    $string = anonymize_mac($string);
    return $string;
}

sub anonymize_ip_prefix($){
    my $string = shift;
    $string =~ s/(?<!\d\.)$ip_prefix_regex(?!\.\d+\.\d+)/<ip_x.x.x>./go;
    $string =~ s/(?<!\d\.)$subnet_mask_regex/<subnet_x.x.x.x>/go;
    $string = anonymize_mac($string);
    return $string;
}

sub anonymize_user($){
    my $string = shift;
    $string =~ s/(-$user_name$arg_sep)$user/$1<user>/go;
    $string =~ s/\/home\/$user_regex/\/home\/<user>/go;
    $string =~ s/($user_name$arg_sep)\S+/$1<user>/go;
    return $string;
}

sub anonymize_password($){
    my $string = shift;
    my $pw_regex = qr/(?:'[^']+'|"[^"]+"|[^\s]+)/;
    # openssl uses -passin switch
    $string =~ s/(-${pass_word_phrase}$arg_sep)$pw_regex/$1<password>/go;
    #$string =~ s/(\bcurl\s.*?-[A-Za-tv-z]*u(?:=|\s+)?)[^:\s]+:[^\s]+/$1<user>:<password>/go;
    $string =~ s/(\bcurl\s.*?-[A-Za-tv-z]*u[=\s]*)[^\s:]+:$pw_regex/$1<user>:<password>/go;
    $string =~ s/\b(${user_name}$arg_sep)\S+([\,\.\s]+${pass_word_phrase}$arg_sep)$pw_regex/$1<user>$2<password>/go;
    return $string;
}

sub anonymize_port($){
    my $string = shift;
    $string =~ s/:\d+(?!\.?[\w-])/:<port>/go;
    return $string;
}

##############################
# this host based anonymization will sometimes anonymize class names in debug messages and logs, isJavaException & isPythonTraceback minimize it, but there is always a slight chance of not anonymization sensitive hosts if using host name anonymization must double check the output
# the alternative is to not use hostname/domain/fqdn anonymization and instead put your domains and host naming conventions in to anonymize_custom.conf and use --custom

sub anonymize_hostname($){
    my $string = shift;
    if($skip_java_exceptions){
        return $string if isJavaException($string);
    }
    if($skip_python_tracebacks){
        return $string if isPythonTraceback($string);
        return $string if isGenericPythonLogLine($string);
    }
    # since digits are now valid hostnames, must use the following to avoid replacing on timestamps
    #  negative lookbehind for NN:
    #  negative lookahead for :NN:NN
    #$string =~ s/(?<!\w\]\s)(?<!\d{2}:)(?!\d{1,2}:\d{2}(?:\d{3})?\s|$ignore_regex|\d+[^A-Za-z0-9])$hostname_regex(?<!\.java)(?<!\sid):(\d{1,5}(?:[^A-Za-z]|$))/<hostname>:$1/go;
    # (?!\d+[^A-Za-z0-9] prevents the match from being just a number as updated hostname_regex permits numbers as valid host identifiers that are being used in the wil in FQDNs
    # (?!<\.) prevents hostname matching mid-filename otherwise matches filename extensions - XXX: however this is slightly dangerous as sentences without a space after the full stop won't be anonymized
    # XXX: shouldn't really do negative lookbehind for .py as that's a valid IANA domain - review this
    # (?!\d+T\d+:\d+) = don't match 2018-01-01T00:00:00 => 2018-01-<hostname>:00:00
    # (?<!\$) - ignore Java SomeClass$method:20
    # (?!\(\w+\.java:\d+\)) - ignore Java stack traces eg. at SomeClass(Thread.java;789)
    $string =~ s/(?<!\w\]\s)
                 (?<!\.)
                 (?<!\$)
                 (?!\d+T\d+:\d+)
                 (?!\d+[^A-Za-z0-9]
                 |$ignore_regex)
                 $hostname_regex
                 (?i:(?<!\.java)
                 (?<!\.py)
                 (?<!\sid))
                 :(\d{1,5})
                 (?!\.?\w)/<hostname>:$1/gox;
    $string =~ s/\b(?:ip-10-\d+-\d+-\d+|ip-172-1[6-9]-\d+-\d+|ip-172-2[0-9]-\d+-\d+|ip-172-3[0-1]-\d+-\d+|ip-192-168-\d+-\d+)\b(?!-\d)/<aws_hostname>/go;
    $string =~ s/(\w+:\/\/)$hostname_regex/$1<hostname>/go;
    return $string;
}

sub anonymize_domain($){
    my $string = shift;
    if($skip_java_exceptions){
        return $string if isJavaException($string);
    }
    # (?!", line \d+) - prevent matching Python tracebacks
    # check isPythonTraceback instead
    if($skip_python_tracebacks){
        return $string if isPythonTraceback($string);
        return $string if isGenericPythonLogLine($string);
    }
    # using stricter domain_regex_strict which requires domain.tld format and not just tld
    $string =~ s/(?!$ignore_regex)$domain_regex_strict(?!\.[A-Za-z])(?!\(\w+\.java:\d+\))(\b|$)/<domain>/go;
    $string =~ s/\@$domain_regex/\@<domain>/go;
    return $string;
}

sub anonymize_fqdn($){
    my $string = shift;
    if($skip_java_exceptions){
        return $string if isJavaException($string);
    }
    # (?!", line \d+) - prevent matching Python tracebacks
    # use isPythonTraceback instead
    if($skip_python_tracebacks){
        return $string if isPythonTraceback($string);
        return $string if isGenericPythonLogLine($string);
    }
    # variable length lookbehind is not implemented, so can't use full $tld_regex (which might be too permissive anyway)
    $string =~ s/(?!$ignore_regex)$fqdn_regex(?!\.[A-Za-z])(?!\(\w+\.java:\d+\))(\b|$)/<fqdn>/goi;
    return $string;
}

sub isGenericPythonLogLine(){
    my $line=shift;
    $line =~ /\s$filename_regex.py:\d+ - loglevel=[\w\.]+\s*$/
}

sub anonymize_email($){
    my $string = shift;
    $string =~ s/$email_regex/<email>/go;
    return $string;
}

# initially built to anonymize 'curl -iv' outputs
sub anonymize_proxy($){
    my $string = shift;
    # not just applying --host and --ip here as it may strip too much from a larger output
    # this allows the user to choose and additionally specify --host and --ip if desired
    $string =~ s/proxy $host_regex port \d+/proxy <proxy_host> port <proxy_port>/go;
    $string =~ s/Trying $ip_regex/Trying <proxy_ip>/go;
    $string =~ s/Connected to $host_regex \($ip_regex\) port \d+/Connected to <proxy_host> \(<proxy_ip>\) port <proxy_port>/go;
    # * Connection #0 to host <host> left intact
    $string =~ s/(Connection #\d+ to host )$host_regex/$1<proxy_host>/go;
    # Via: 1.1 10.1.100.218 (Product Type and version)
    $string =~ s/(Via:\s\S+\s)$ip_regex.*/$1<proxy_ip>/go;
    # trying to anonymize passwords on the CLI will match too aggressively
    #$string =~ s/curl\s.+U.+\s//go;
    # if you are anonymization proxy addresses then you almost certainly want to anonymize the http_auth too
    $string = anonymize_http_auth($string);
    return $string;
}

sub anonymize_http_auth($){
    my $string = shift;
    $string =~ s/(https?:\/\/)[^:]+:[^\@]*\@/$1<user>:<password>\@/go;
    $string =~ s/([\w-]*[\s-](?:Authentication|Authorization):\s*(?:Basic|Digest)\s+).+$/$1<auth_token>/go;
    # Proxy auth using Basic with user '.+'
    $string =~ s/(Proxy auth using \w+ with user )(['"]).+(['"])/$1'<proxy_user>$2$3/go;
    $string =~ s/(\btoken:\s+)[A-Za-z0-9]+/$1<token>/go;
    return $string;
}

sub anonymize_kerberos($){
    my $string = shift;
    if($string =~ /\/_HOST\@/){
        # only take the realm off not the
        $string =~ s/$user_regex\/_HOST\@$domain_regex/<kerberos_primary>\/_HOST\@<kerberos_realm>/go;
    } else {
        # krb5_principal_regex is too permission here since it's designed to permit user input, not to differentiate between arbitrary tokens and definitely kerberos principals
        $string =~ s/\b$user_regex(?:\/$hostname_regex)?\@$domain_regex\b/<kerberos_principal>/go;
    }
    return $string;
}

sub anonymize_host($){
    my $string = shift;
    $string = anonymize_fqdn($string);
    $string = anonymize_domain($string);
    $string = anonymize_hostname($string);
    return $string;
}
##############################

sub anonymize_network($){
    my $string = shift;
    $string = anonymize_cisco($string);
    $string = anonymize_screenos($string);
    $string = anonymize_junos($string);
    $string = anonymize_network_generic($string);
    return $string;
}

sub anonymize_network_generic($){
    my $string = shift;
    $string =~ s/username .*/username <username>/;
    $string =~ s/syscontact .*/syscontact <syscontact>/;
    return $string;
}

sub anonymize_cisco($){
    my $string = shift;
    $string =~ s/username .+ (?:password|secret) .*?$/username <username> password <password>/g;
    $string =~ s/password .*?$/password <cisco_password>/g;
    $string =~ s/secret .*?$/secret <secret>/g;
    $string =~ s/\smd5\s+.*?$/ md5 <md5>/g;
    $string =~ s/\scommunity\s+.*$/ community <community>/g;
    $string =~ s/(standby\s+\d+\s+authentication).*/$1 <auth>/g;
    $string =~ s/\sremote-as\s\d+/remote-as <AS>/g;
    $string =~ s/description\s.*$/description <cisco_description>/g;
    $string = anonymize_network_generic($string) unless $network;
    return $string;
}

sub anonymize_screenos($){
    my $string = shift;
    $string =~ s/set admin (name|user|password) "?.+"?/set admin $1 <anonymized>/g;
    $string =~ s/set snmp (community|host) "?.+"?/set snmp $1 <anonymized>/g;
    $string =~ s/ md5 "?.+"?/ md5 <md5>/g;
    $string =~ s/ key [^\s]+ (?:!enable)/ key <key>/g;
    $string =~ s/set nsmgmt init id [^\s]+/set nsmgmt init id <id>/g;
    $string =~ s/preshare .+? /preshare <psk> /g;
    $string = anonymize_network_generic($string) unless $network;
    return $string;
}

sub anonymize_junos($){
    my $string = shift;
    $string =~ s/pre-shared-key\s.*/pre-shared-key <psk>/g;
    $string =~ s/\shome\s+.*/ home <home>/g;
    $string = anonymize_network_generic($string) unless $network;
    return $string;
}

# ============================================================================ #
# main()
if(@files){
    foreach my $file (@files){
        open(my $fh, $file) or die "Failed to open file '$file': $!\n";
        while(<$fh>){ print anonymize($_) }
    }
} else {
    while(<STDIN>){ print anonymize($_) }
}
