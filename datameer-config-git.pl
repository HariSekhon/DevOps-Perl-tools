#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 23:53:45 +0000 (Thu, 05 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://www.datameer.com/documentation/current/Accessing+Datameer+Using+the+REST+API

my @valid_types = qw/
    workbook
    connections
    import-job
    export-job
    infographics
    dashboard
    /;
$DESCRIPTION = "Program to revision control Datameer configuration in Git

Inspired by Rancid and the Datameer checks from the Advanced Nagios Plugins Collection

Fetches configuration via the Datameer Rest API and writes it to files under specified Git directory repo, then commits those files to Git

Requirements:

- Datameer user with ADMIN assigned inside Datameer in order to fetch all configs (otherwise will only fetch some it has access to)
- a valid Git repository checkout top level directory
- a safety dot file '.datameer.git' at the top level of the git directory checkout indicating that this repo is owned by this program before it will write to it

Can optionally specify just a subset of one or more of the following config types (fetches all config of given types or all configs of all of the following types if none are specified):

" . join("\n", @valid_types) . " 

Tested on Datameer 3.0.11";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;
use Data::Dumper;
use Fcntl ':flock';
use File::Spec;
use LWP::Simple '$ua';
#use Time::HiRes 'sleep';

$Data::Dumper::Terse  = 1;
$Data::Dumper::Indent = 1;

my $dir;
my $git = "git";
my $no_git;
my $quiet;
my $type;
my $skip_error;

%options = (
    %datameer_options,
    "d|git-dir=s",  [ \$dir,        "Git repo's top level directory" ],
    "git-binary=s", [ \$git,        "Path to git binary if not in \$PATH ($ENV{PATH})" ],
    "no-git",       [ \$no_git,     "Do not commit to Git (must still specify a directory to download it but skips checks for .git since it doesn't invoke Git)" ],
    "T|type=s",     [ \$type,       "Only fetch configs for these types in Datameer (comma separated list, see full list in --help description)" ],
    "q|quiet",      [ \$quiet,      "Quiet mode" ],
    #"skip-error",   [ \$skip_error, "Skip errors from Datameer server" ],
);
@usage_order = qw/host port user password git-dir git-binary no-git type quiet/;

set_timeout_max(3600);
set_timeout_default(600);

get_options();
$verbose++ unless $quiet;

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$dir = validate_directory($dir, 0, "git");
$dir = File::Spec->rel2abs($dir);
$git = which($git, 1);
$git = validate_file($git, 0, "git binary");
$git =~ /\/git$/ or usage "--git-binary must be the path to the 'git' command!";
vlog_options "commit to git", ( $no_git ? "False" : "True" );
my @selected_types;
if($type){
    foreach $type (split(/\s*,\s*/, $type)){
        if(grep { $type eq $_ } @valid_types){
            push(@selected_types, $type);
        } else {
            print "invalid type '$type' specified, see list of valid types below\n";
            usage;
        }
    }
}
if(@selected_types){
    @selected_types = uniq_array(@selected_types);
} else {
    @selected_types = @valid_types;
}
vlog_options "types",       "@selected_types";
#vlog_options "skip-error",  ( $skip_error ? "True" : "False" );

vlog2;
set_timeout();
set_http_timeout(30);

$status = "OK";

chdir($dir) or die "failed to chdir to git directory $dir\n";
unless($no_git){
    ( -d ".git" ) or die "'$dir' is not a Git repository!\n";
}
( -f ".datameer.git" ) or die "'$dir' does not contain the safety touch file '.datameer.git' to ensure that you intend to write and commmit to this repo\n";

open my $lock_fh, "$dir"; # without quotes my tries to take $dir
flock $lock_fh, LOCK_EX|LOCK_NB or die "Failed to acquire lock on '$dir', another instance of this program must be running!\n";

my $url = "http://$host:$port/rest";

my $json;
my $id;
my $filename;
my $fh;
my $output;
my $req;
my $response;
$ua->show_progress(1) if $debug;
foreach $type (@selected_types){
    vlog "fetching all configuration for: $type";
    $json = datameer_curl "$url/$type", $user, $password;
    # iterate over ids, fetch and save to file hierarchy under git
    foreach $json (@{$json}){
        defined($json->{"id"}) or die "Error: Datameer returned a $type with no id!";
        $id = $json->{"id"};
        $id =~ /^(\d+)$/ or die "Error: Datameer returned a non-integer id for $type, investigation required";
        $id = $1;
        if($type eq "import-job" and $json->{"path"} =~ /^\/.system\//){
            # skip system import jobs since they error when trying to pull them anyway
            vlog "skipping $type $id with path /.system/...";
            next;
        }
        vlog "fetching configuration for $type id $id";
        vlog3 "GET $url/$type/$id";
        $req = HTTP::Request->new('GET', "$url/$type/$id");
        $req->authorization_basic($user, $password) if (defined($user) and defined($password));
        $response = $ua->request($req);
        $json  = $response->content;
        vlog3 "returned HTML:\n\n" . ( $json ? $json : "<blank>" ) . "\n";
        vlog2 "http status code:     " . $response->code;
        vlog2 "http status message:  " . $response->message . "\n";
        unless($response->code eq "200"){
            if($skip_error){
                print "failed to fetch $type id $id, skipping...\n";
                next;
            } else {
                quit("UNKNOWN", $response->code . " " . $response->message);
            }
        }
        unless($json){
            quit("CRITICAL", "blank content returned from '$url/$type/$id'");
        }
        $output = Dumper($json) || die "Failed to convert json config to string: $!";
        $output =~ s/^'//;
        $output =~ s/\n'//;
        vlog3($output);
        ( -d $type ) or mkdir $type or die "Failed to create directory '$dir': $!\n";
        $filename = "$dir/$type/$id";
        vlog "writing config to file '$filename'";
        open ($fh, ">", $filename) or die "Failed to open file '$filename': $!\n";
        print $fh $output or die "Failed to write to file '$filename': $!\n";
        close $fh;
        vlog2;
        #sleep 0.5
    }
}

unless($no_git){
    vlog "committing any changes to git";
    my $cmd = "$git add . && $git commit -m \"updated datameer config\"";
    vlog2 "cmd: $cmd";
    $output = `$cmd`;
    my $returncode = $?;
    vlog2 "output:\n\n$output\n";
    vlog2 "returncode: $returncode\n";
    if($returncode != 0){
        unless($output =~ "nothing to commit"){
            print "ERROR:\n\n$output\n";
            exit $returncode;
        }
    }
    $output =~ /\d+ files? changed|\d+ insertion|\d+ deletion/i and print "$output\n";
}
