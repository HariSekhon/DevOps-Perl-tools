#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 23:53:45 +0000 (Thu, 05 Dec 2013)
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
- a valid Git repository checkout (specify the top level directory to --git-dir)
- a safety dot file '.datameer.git' at the top level of the git directory checkout indicating that this repo is owned by this program before it will write to it

Can optionally specify just a subset of one or more of the following config types (fetches all config of given types or all configs of all of the following types if none are specified):

" . join("\n", @valid_types) . "

Tested on Datameer 3.0.11 and 3.1.1";

$VERSION = "0.5.1";

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
use POSIX 'ceil';
use Time::HiRes;

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

set_timeout_max(36000);
set_timeout_default(600);

get_options();
$verbose++ unless $quiet;

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
# Putting rel2abs after validate re-taints the $dir, but putting it before rel2abs assumes "." on undefined $dir, avoiding the validation defined check, so check defined before rel2abs and then validate final $dir format before usage
$dir or usage "git directory not defined";
$dir = File::Spec->rel2abs($dir);
$dir = validate_directory($dir, "git");
$git = which($git, 1);
$git = validate_file($git, "git binary");
$git =~ /\/git$/ or usage "--git-binary must be the path to the 'git' command!";
vlog_option "commit to git", ( $no_git ? "False" : "True" );
my %selected_types;
if($type){
    foreach $type (split(/\s*,\s*/, $type)){
        if(grep { $type eq $_ } @valid_types){
            $selected_types{$type} = 0;
        } else {
            print "invalid type '$type' specified, see list of valid types below\n";
            usage;
        }
    }
}
if(not %selected_types){
    %selected_types = map { $_ => 0 } @valid_types;
}
vlog_option "types",       join(" ", sort keys %selected_types);
#vlog_option "skip-error",  ( $skip_error ? "True" : "False" );

vlog2;
set_timeout();
set_http_timeout(30);

$status = "OK";

chdir($dir) or die "failed to chdir to git directory '$dir': $!\n";
unless($no_git){
    ( -d ".git" ) or die "'$dir' is not a Git repository!\n";
}
( -f ".datameer.git" ) or die "'$dir' does not contain the safety touch file '.datameer.git' to ensure that you intend to write and commmit to this repo\n";

open my $lock_fh, "$dir"; # without quotes my tries to take $dir
flock $lock_fh, LOCK_EX|LOCK_NB or die "Failed to acquire lock on '$dir', another instance of this program must be running!\n";

my $url = "http://$host:$port/rest";

my $json;
my $content;
my $id;
my $filename;
my $fh;
my $output;
my $req;
my $response;
my $start_time = time;
my $start_time_type;
my %timings;
$ua->show_progress(1) if $debug;
vlog "fetching all configurations for: " . join(" ", sort keys %selected_types);
foreach $type (sort keys %selected_types){
    vlog "fetching configurations for: $type";
    $start_time_type = time;
    try {
        $json = datameer_curl "$url/$type", $user, $password;
    };
    catch {
        quit "CRITICAL", "failed to query datameer: $@";
    };
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
        $content  = $response->content;
        vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
        vlog2 "http status code:     " . $response->code;
        vlog2 "http status message:  " . $response->message . "\n";
        unless($response->code eq "200"){
            if($skip_error){
                print "failed to fetch $type id $id, skipping...\n";
                next;
            } else {
                quit("UNKNOWN", $response->code . " " . $response->message . "\n\n" . $content);
            }
        }
        unless($json){
            quit("CRITICAL", "blank content returned from '$url/$type/$id'");
        }
        # This ends up escaping \u0000 unicode and makes the saved files invalid to be PUT back to Datameer
        #$output = Dumper($json) || die "Failed to convert json config to string: $!";
        #$output =~ s/^'//;
        #$output =~ s/\n'//;
        #vlog3($output);
        ( -d $type ) or mkdir $type or die "Failed to create directory '$dir': $!\n";
        $filename = "$dir/$type/$id";
        $json = isJson($content) or die "failed to interpret json for workbook id '$id' in order to pretty print\n";
        $json = to_json($json, { pretty => 1}) or die "Failed to convert json for pretty printing";
        vlog2 "writing config to file '$filename'";
        open ($fh, ">", $filename) or die "Failed to open file '$filename': $!\n";
        print $fh $json or die "Failed to write to file '$filename': $!\n";
        close $fh;
        $selected_types{$type}++;
        vlog2;
        #sleep 0.5
    }
    $timings{$type} = ceil(time - $start_time_type);
    plural $selected_types{$type};
    vlog "finished fetching $type: $selected_types{$type} fetched in $timings{$type} secs"
}
my $total_time = ceil(time - $start_time);

vlog "\nCompleted all configuration fetching in $total_time secs:\n";
foreach(sort keys %selected_types){
    vlog sprintf("%-10s\t%4d fetched in %4d secs", $_, $selected_types{$_}, $timings{$_});
}
vlog;

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
