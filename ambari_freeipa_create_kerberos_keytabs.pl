#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2014-11-23 17:12:26 +0000 (Sun, 23 Nov 2014)
#
#  https://github.com/harisekhon/toolbox
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Generates Ambari Kerberos principals and keytabs in FreeIPA / Redhat IPA for use in Hadoop on the Hortonworks Data platform

MAKE SURE YOU 'KINIT' BEFORE RUNNING THIS PROGRAM - you will need to have a valid Kerberos ticket to create IPA users.

Takes a CSV file as an argument, Ambari generates this CSV file as part of the Enable Security wizard. You can write your own CSV for other Hadoop distributions or other purposes as long as you use the same format:

Host,Description,Principal,Keytab Name,Export Dir,User,Group,Octal perms

Requirements:

This program uses the 'ipa' command line tool to generate the Kerberos principals (ipa-admintools package). This requires a valid Kerberos ticket.

Re-exporting keytabs invalidates all currently existing keytabs for given principals - will prompt for confirmation before proceeding to export keytabs.

Requires LDAP bind credentials if exporting keytabs (eg. -d uid=admin,cn=users,cn=accounts,dc=domain,dc=com -w mypassword)

Tested on HDP 2.1 and Ambari 1.5 with FreeIPA 3.0.0";

# Heavily leverages personal library for lots of error checking

# Relying on Kerberos ticket doesn't work in IPA for fetching keytab and results in error code 9 - \"SASL Bind failed Local error (-2) SASL(-1): generic failure: GSSAPI Error: Unspecified GSS failure. Minor code may provide more information (Server ldap/localhost@LOCAL not found in Kerberos database)!]\"

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use File::Temp ':POSIX';
use File::Copy;
use File::Path 'make_path';
use POSIX;

$github_repo = "toolbox";

my $ipa_server;
my $bind_dn;
my $bind_password;

env_vars("IPA_SERVER",        $ipa_server);
env_vars("IPA_BIND_DN",       $bind_dn);
env_vars("IPA_BIND_PASSWORD", $bind_password);

my $KINIT = "/usr/bin/kinit";
my $KLIST = "/usr/bin/klist";

my $IPA="/usr/bin/ipa";
my $IPA_GETKEYTAB="/usr/sbin/ipa-getkeytab";

# fake email makes sure we pass IPA user creation, FreeIPA is fussy about the email format and it's possible to use principals in Ambari such as LOCAL/LOCALDOMAIN that IPA will not allow.
# If this is not set it will try to use the principal without host component as the email address, which may or may not fail
my $EMAIL="admin\@hari.sekhon.com";

my $csv;
$ipa_server = "localhost" unless $ipa_server;
my @output;
$verbose = 2;
my $quiet;

%options = (
    "f|file=s"          =>  [ \$csv,            "CSV file exported from Ambari 'Enable Security' containing the list of Kerberos principals and hosts" ],
    "s|server=s"        =>  [ \$ipa_server,     "IPA server to export the keytabs from via LDAP. Defaults to localhost, otherwise requires FQDN in order to validate the LDAP SSL certificate [would otherwise result in the error 'Simple bind failed'] (default: localhost, \$IPA_SERVER)" ],
    "d|bind-dn=s"       => [ \$bind_dn,         "IPA LDAP Bind DN for exporting keytabs (\$IPA_BIND_DN)" ],
    "p|bind-password=s" => [ \$bind_password,   "IPA LDAP Bind password for exporting keytabs (\$IPA_BIND_PASSWORD)" ],
    "q|quiet"           => [ \$quiet,           "Quiet mode" ],
);
splice @usage_order, 6, 0, qw/file server bind-dn bind-password quiet/;

get_options();

$csv    = validate_file($csv, 0, "Principals CSV");

$verbose-- if $quiet;

vlog2;
set_timeout(60);

$status = "OK";

# simple check to see if we have a kerberos ticket in cache
cmd("$KLIST", 1);
#@output = cmd("$KLIST");
#vlog2;
#
#my $found_princ = 0;
#foreach(@output){
#    /^Default principal:\s*$user/ and $found_princ++;
#}
#
#@output = cmd("$KINIT $user <<EOF\n$password\nEOF\n", 1) unless $found_princ;
#vlog2;

# error handling is handled in my library function open_file()
my $fh = open_file $csv;
vlog2;

my %ipa;
foreach my $type (qw/host user service/){
    vlog2 "fetching IPA $type list";
    @output = cmd("$IPA $type-find", 1);
    foreach(@output){
        if(/^\s*Host\s+name:\s+(.+)\s*$/  or
           /^\s*User\s+login:\s+(.+)\s*$/ or
           /^\s*Principal:\s+(.+)\s*$/
          ){
            push(@{$ipa{$type}}, $1);
        }
    }
}
vlog2;

my @principals;

while (<$fh>){
    chomp;
    #(my $host, my $description, my $principal, my $keytab, my $keytab_dir, my $owner, my $group, my $perm) = split($_, 8);
    /^(.+?),(.+?),(.+?),(.+?),(.+?),(.+?),(.+?),(.+)$/ or die "ERROR: invalid CSV format detected on line $.: '$_' (expected 8 comma separated fields)\n";
    my $host        = $1;
    my $description = $2;
    my $principal   = $3;
    my $keytab      = $4;
    my $keytab_dir  = $5;
    my $owner       = $6;
    my $group       = $7;
    my $perm        = $8;
    ###
    $host =~ /^($host_regex)$/ or die "ERROR: invalid host '$host' (field 1) on line $.: '$_' - failed host regex validation\n";
    $host = $1;
    $description =~ /^([\w\s-]+)$/ or die "ERROR: invalid description '$description' (field 2) on line $.: '$_' - may only contain alphanumeric characters";
    $description = $1;
    $principal   =~ /^(($user_regex)(?:\/($host_regex))?\@($host_regex))$/ or die "ERROR: invalid/unrecognized principal format found on line $.: '$principal'\n";
    $principal          = $1;
    my $user            = $2;
    my $host_component  = $3;
    if($host_component and $host_component ne $host){
        die "ERROR: host '$host' and host component '$host_component' from principal '$principal' do not match on line $.: '$_'\n"
    }
    my $domain          = $4;
    $keytab      =~ /^($filename_regex)$/ or die "ERROR: invalid keytab file name '$keytab' (field 4) on line $.: '$_' - failed regex validation\n";
    $keytab = $1;
    $keytab_dir  =~ /^($filename_regex)$/ or die "ERROR: invalid keytab directory '$keytab_dir' (field 5) on line $.: '$_' - failed regex validation\n";
    $keytab_dir = $1;
    $owner =~ /^($user_regex)$/ or die "ERROR: invalid owner '$owner' (field 6) on line $.: '$_' - failed regex validation\n";
    $owner = $1;
    $group =~ /^($user_regex)$/ or die "ERROR: invalid group '$group' (field 6) on line $.: '$_' - failed regex validation\n";
    $group = $1;
    $perm =~ /^(0?\d{3})$/ or die "ERROR: invalid perm '$perm' (field 6) on line $.: '$_' - failed regex validation\n";
    $perm = $1;
    push(@principals, [$host, $description, $principal, $keytab, $keytab_dir, $owner, $group, $perm, $user, $domain]);
}
close $fh;

vlog2 "Creating IPA Kerberos principals:\n";
foreach(@principals){
    my ($host, $description, $principal, $keytab, $keytab_dir, $owner, $group, $perm, $user, $domain) = @{$_};
    my $email;
    if($EMAIL){
        $email = $EMAIL
    } else {
        $email = "$user\@$domain";
    }
    if($principal =~ /\//o){
        if(not grep { $host eq $_ } @{$ipa{"host"}}){
            vlog2 "creating host '$host' in IPA system";
            cmd("$IPA host-add --force '$host'");
        } else {
        vlog3 "IPA host '$host' already exists, skipping...";
        }
        if(not grep { $principal eq $_ } @{$ipa{"service"}}){
            vlog2 "creating host service principal '$principal'";
            cmd("$IPA service-add --force '$principal'", 1);
        } else {
            vlog2 "service principal '$principal' already exists, skipping...";
        }
    } else {
        if(not grep { $user eq $_ } @{$ipa{"user"}}){
            vlog2 "creating user principal '$principal'";
            cmd("$IPA user-add --first='$description' --last='$description' --displayname='$principal' --email='$email' --principal='$principal' --random '$user'", 1);
        } else {
            vlog2 "user principal '$principal' already exists, skipping...";
        }
    }
}

print "\nAbout to export keytabs:

WARNING: re-exporting keytabs will invalidate all currently existing keytabs for these principals.

Are you sure that you want to export keytabs?(y/N) ";
my $response = <STDIN>;
chomp $response;
vlog2;

unless($response =~ /^y(es)?$/i){
    print "Not exporting keytabs\n";
    exit 0;
}

vlog2 "\nExporting IPA Kerberos keytabs from IPA server '$ipa_server' via LDAPS:\n\n";

$ipa_server      = validate_host($ipa_server, "KDC");
if($ipa_server ne "localhost"){
    vlog2 "checking IPA server has been given as an FQDN in order for successful bind with certificate validation";
    $ipa_server  = validate_fqdn($ipa_server, "KDC");
}
$bind_dn       = validate_ldap_dn($bind_dn,        "IPA bind") if $bind_dn;
$bind_password = validate_password($bind_password, "IPA bind") if $bind_password;
vlog2;

my %dup_princs;
foreach(@principals){
    my ($host, $description, $principal, $keytab, $keytab_dir, $owner, $group, $perm, $user, $domain) = @{$_};
    if(defined($dup_princs{$principal})){
        if($dup_princs{$principal}{"keytab"} eq "$keytab_dir/$keytab"){
            # harmless we'll overwrite the 
            warn "WARNING: duplicate principal '$principal' detected ($description), but keytab is the same '$keytab_dir/$keytab' so this shouldn't cause problems\n" if $verbose >= 3;
        } else {
            die "ERROR: duplicate principal '$principal' detected with differing keytabs ('$dup_princs{$principal}{keytab}' vs '$keytab_dir/$keytab'), something will break if we do this!\n";
        }
    }
    $dup_princs{$principal}{"keytab"} = "$keytab_dir/$keytab";
}

my $timestamp = strftime("%F_%H%M%S", localtime);
my $keytab_backups = "keytab-backups-$timestamp";
vlog2 "\nwill backup any existing keytabs to sub-directory $keytab_backups at same location as originals\n";
foreach(@principals){
    my ($host, $description, $principal, $keytab, $keytab_dir, $owner, $group, $perm) = @{$_};
    if( -d $keytab_dir ){
        #vlog2 "found keytab directory '$keytab_dir'";
        ( -w $keytab_dir ) or die "ERROR: keytab directory '$keytab_dir' is not writeable!\n";
    } else {
        vlog2 "creating keytab directory '$keytab_dir'";
        make_path($keytab_dir, "mode" => "0700") or die "ERROR: failed to create directory: $!\n";
    }
    if(-f "$keytab_dir/$keytab"){
        my $keytab_backup_dir = "$keytab_dir/$keytab_backups";
        unless ( -d $keytab_backup_dir ){
            make_path($keytab_backup_dir, "mode" => "0700") or die "ERROR: failed to create backup directory '$keytab_backup_dir': $!\n";
        }
        vlog3 "backing up existing keytab '$keytab_dir/$keytab' to $keytab_backup_dir";
        move("$keytab_dir/$keytab", "$keytab_backup_dir/") or die "ERROR: failed to back up existing keytab: $!";
    }
    my $tempfile = tmpnam();
    vlog2 "exporting keytab for principal '$principal' to '$keytab_dir/$keytab'";
    @output = cmd("$IPA_GETKEYTAB -s '$ipa_server' -p '$principal' -D '$bind_dn' -w '$bind_password' -k '$tempfile'", 1);
    move($tempfile, "$keytab_dir/$keytab") or die "ERROR: failed to move temp file '$tempfile' to '$keytab_dir/$keytab': $!";
    my $uid = getpwnam $owner;
    my $gid = getgrnam $group;
    unless(defined($uid)){
        warn "WARNING: failed to resolve UID for user '$owner', defaulting to UID 0 for keytab '$keytab'\n" if($verbose >= 3);
        $uid = 0;
    }
    unless(defined($gid)){
        warn "WARNING: failed to resolve GID for group '$group', defaulting to GID 0 for keytab '$keytab'\n" if ($verbose >= 3);
        $gid = 0;
    }
    chown($uid, $gid, "$keytab_dir/$keytab") or die "ERROR: failed to chmod keytab '$keytab_dir/$keytab' to $perm: $!";
    chmod($perm, "$keytab_dir/$keytab") or die "ERROR: failed to chmod keytab '$keytab_dir/$keytab' to $perm: $!";
}

print "Complete\n";
exit 0;
