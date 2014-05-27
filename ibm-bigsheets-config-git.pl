#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2014-05-27 (based on datameer-config-git.pl from 2013-12-05)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://www.bigsheets.com/documentation/current/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Program to revision control IBM BigSheets workbooks to Git

Inspired by Rancid and datameer-config-git.pl from this same Toolbox

Fetches configuration via the IBM BigSheets Rest API and writes it to files under specified Git directory repo, then commits those files to Git

Requirements:

- IBM BigInsights Console admin user in order to fetch all configs
- a valid Git repository checkout (specify the top level directory to --git-dir)
- a safety dot file '.bigsheets.git' at the top level of the git directory checkout indicating that this repo is owned by this program before it will write to it

Tested on BigInsights 2.1.2";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use Fcntl ':flock';
use File::Spec;
use JSON;
use LWP::Simple '$ua';
#use Time::HiRes 'sleep';

$Data::Dumper::Terse  = 1;
$Data::Dumper::Indent = 1;

my $dir;
my $git = "git";
my $no_git;
my $quiet;
my $output;
my $skip_error;

set_port_default(8080);

env_creds("BIGINSIGHTS", "IBM BigInsights Console");

my $api = "data/controller";

%options = (
    %hostoptions,
    %useroptions,
    %tlsoptions,
    "d|git-dir=s",  [ \$dir,        "Git repo's top level directory" ],
    "git-binary=s", [ \$git,        "Path to git binary if not in \$PATH ($ENV{PATH})" ],
    "no-git",       [ \$no_git,     "Do not commit to Git (must still specify a directory to download it but skips checks for .git since it doesn't invoke Git)" ],
    "q|quiet",      [ \$quiet,      "Quiet mode" ],
    #"skip-error",   [ \$skip_error, "Skip errors from BigInsights Console for single workbooks, attempt to fetch other workbooks" ],
);
@usage_order = qw/host port user password git-dir git-binary no-git quiet/;

set_timeout_max(36000);
set_timeout_default(600);

get_options();
$verbose++ unless $quiet;

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
# Putting rel2abs after validate re-taints the $dir, but putting it before rel2abs assumes "." on undefined $dir, avoiding the validation defined check, so check defined before rel2abs and then validate final $dir format before usage
$dir or usage "git directory not defined";
$dir = File::Spec->rel2abs($dir);
$dir = validate_directory($dir, 0, "git");
$git = which($git, 1);
$git = validate_file($git, 0, "git binary");
$git =~ /\/git$/ or usage "--git-binary must be the path to the 'git' command!";
vlog_options "commit to git", ( $no_git ? "False" : "True" );

our $protocol = "http";

tls_options();

vlog2;
set_timeout();
set_http_timeout(30);

my $url_prefix = "$protocol://$host:$port";
my $url = "$url_prefix/bigsheets/api/workbooks";

$status = "OK";

chdir($dir) or die "failed to chdir to git directory '$dir': $!\n";
unless($no_git){
    ( -d ".git" ) or die "'$dir' is not a Git repository!\n";
}
( -f ".bigsheets.git" ) or die "'$dir' does not contain the safety touch file '.bigsheets.git' to ensure that you intend to write and commmit to this repo\n";

open my $lock_fh, "$dir"; # without quotes my tries to take $dir
flock $lock_fh, LOCK_EX|LOCK_NB or die "Failed to acquire lock on '$dir', another instance of this program must be running!\n";

my $filename;
my $fh;
my $name;

vlog "fetching bigsheets workbooks";
my $start_time = time;

######################
# XXX: taken from check_bim_biginsights_bigsheets_workbook.pl
# TODO: library this
validate_resolvable($host);
vlog2 "querying IBM BigInsights Console";
vlog3 "HTTP GET $url (basic authentication)";
$ua->show_progress(1) if $debug;
my $req = HTTP::Request->new('GET', $url);
$req->authorization_basic($user, $password) if (defined($user) and defined($password));
my $response = $ua->request($req);
my $content  = $response->content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http status code:     " . $response->code;
vlog2 "http status message:  " . $response->message . "\n";
my $json;
my $additional_information = "";
if($json = isJson($content)){
    if(defined($json->{"status"})){
        $additional_information .= ". Status: " . $json->{"status"};
    }
    if(defined($json->{"errorMsg"})){
        $additional_information .= ". Reason: " . $json->{"errorMsg"};
    }
}
unless($response->code eq "200" or $response->code eq "201"){
    quit "CRITICAL", $response->code . " " . $response->message . $additional_information;
}

if(defined($json->{"errorMsg"})){
    if($json->{"errorMsg"} eq "Could not get Job status: null"){
        quit "UNKNOWN", "worksheet job run status: null (workbook not been run yet?)";
    }
    $additional_information =~ s/^\.\s+//;
    quit "CRITICAL", $additional_information;
}
unless($content){
    quit "CRITICAL", "blank content returned from '$url'";
}

try {
    $json = decode_json $content;
};
catch {
    quit "invalid json returned by IBM BigInsights Console at '$url_prefix', did you try to connect to the SSL port without --tls?";
};
vlog3(Dumper($json));
#####################

# iterate over workbooks, fetch and save to file hierarchy under git
defined($json->{"workbooks"}) or die "Error: no 'workbook' field returned from BigInsights Console!";
isArray($json->{"workbooks"}) or die "Error: 'workbooks' field is not an array as expected!";

# TODO: clean this up and dedupe with fetch above
my $json2;
my $json3;
my $errmsg;
foreach my $workbook (@{$json->{"workbooks"}}){
    defined($workbook->{"name"}) or die "Error: no 'name' field for workbook!";
    $name = $workbook->{"name"};
    $name = validate_filename($name, 0, "workbook", 1);
    $filename = "$dir/$name";
    vlog "fetching workbook '$name'";
    vlog3 "GET $url/$name?type=exportmetadata";
    $req = HTTP::Request->new('GET', "$url/$name?type=exportmetadata");
    $req->authorization_basic($user, $password) if (defined($user) and defined($password));
    $response = $ua->request($req);
    $json2  = $response->content;
    vlog3 "returned HTML:\n\n" . ( $json2 ? $json2 : "<blank>" ) . "\n";
    vlog2 "http status code:     " . $response->code;
    vlog2 "http status message:  " . $response->message . "\n";
    $errmsg = "";
    if($json3 = isJson($json2)){
        if(defined($json3->{"status"})){
            $errmsg .= ". Status: " . $json->{"status"};
        }
        if(defined($json3->{"errorMsg"})){
            $errmsg .= ". Reason: " . $json->{"errorMsg"};
        }
    }
    if((not($response->code eq "200" or $response->code eq "201")) or $errmsg){
        if($skip_error){
            print "failed to fetch workbook '$name', skipping...\n";
            next;
        } else {
            quit "CRITICAL", $response->code . " " . $response->message . $errmsg;
        }
    }
    unless($json2){
        quit("CRITICAL", "blank content returned from '$url/$name?type=exportmetadata'");
    }
    $json3 = isJson($json2) or die "failed to interpret json for workbook '$name' in order to pretty print\n";
    defined($json3->{"workbooks"}) or die "Error: workbook '$name' is missing 'workbook' field returned from BigInsights Console!";
    isArray($json3->{"workbooks"}) or die "Error: workbook '$name' has returned 'workbooks' field that is not an array as expected!";
    scalar @{$json3->{"workbooks"}} != 1 and die sprintf("Error: workbook '%s' has returned 'workbooks' array of length %s instead of expected length 1\n", $name, scalar @{$json3->{"workbooks"}});
    $workbook = @{$json3->{"workbooks"}}[0];
    vlog2 "writing workbook '$name' to file '$filename'";
    open ($fh, ">", $filename) or die "Failed to open file '$filename': $!\n";
    print $fh to_json($workbook, { pretty => 1}) or die "Failed to write to file '$filename': $!\n";
    close $fh;
    vlog2;
}

my $total_time = time - $start_time;

plural $total_time;
vlog "\nCompleted fetching and writing all workbook configurations $total_time sec$plural\n";

unless($no_git){
    vlog "committing any changes to git";
    my $cmd = "$git add . && $git commit -m \"updated bigsheets config\"";
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
