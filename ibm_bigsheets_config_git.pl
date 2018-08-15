#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2014-05-27 (based on datameer_config_git.pl from 2013-12-05)
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

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.analyze.doc/doc/bigsheets_restapi.html

$DESCRIPTION = "Program to revision control IBM BigSheets workbooks to Git

Inspired by Rancid and datameer_config_git.pl from this same Tools repo

Fetches configuration via the IBM BigSheets Rest API and writes it to files under specified Git directory repo, then commits those files to Git

Requirements:

- IBM BigInsights Console admin user in order to fetch all configs
- a valid Git repository checkout (specify the top level directory to --git-dir)
- a safety dot file '.bigsheets.git' at the top level of the git directory checkout indicating that this repo is owned by this program before it will write to it

Tested on BigInsights 2.1.2.0";

$VERSION = "0.2.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;
use Fcntl ':flock';
use File::Spec;
use JSON;
use POSIX 'ceil';
use Time::HiRes;
use URI::Escape;

$Data::Dumper::Terse  = 1;
$Data::Dumper::Indent = 1;

my $dir;
my $git = "git";
my $no_git;
my $quiet;
my $output;
my $skip_error;

%options = (
    %biginsights_options,
    "d|git-dir=s",  [ \$dir,        "Git repo's top level directory" ],
    "git-binary=s", [ \$git,        "Path to git binary if not in \$PATH ($ENV{PATH})" ],
    "no-git",       [ \$no_git,     "Do not commit to Git (must still specify a directory to download it but skips checks for .git since it doesn't invoke Git)" ],
    "q|quiet",      [ \$quiet,      "Quiet mode" ],
    #"skip-error",   [ \$skip_error, "Skip errors from BigInsights Console for single workbooks, attempt to fetch other workbooks" ],
);
splice @usage_order, 4, 0, qw/git-dir git-binary no-git quiet/;

set_timeout_max(36000);
set_timeout_default(600);

get_options();
validate_tls();
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

vlog2;
set_timeout();
set_http_timeout(30);

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

curl_bigsheets "/workbooks", $user, $password;

# iterate over workbooks, fetch and save to file hierarchy under git
defined($json->{"workbooks"}) or die "Error: no 'workbook' field returned from BigInsights Console!";
isArray($json->{"workbooks"}) or die "Error: 'workbooks' field is not an array as expected!";

foreach my $workbook (@{$json->{"workbooks"}}){
    defined($workbook->{"name"}) or die "Error: no 'name' field for workbook!";
    $name = $workbook->{"name"};
    $name = validate_filename($name, "workbook", 0, 1);
    $filename = "$dir/$name";
    vlog "fetching workbook '$name'";
    curl_bigsheets "workbooks/" . uri_escape($name) . "?type=exportmetadata", $user, $password;
    defined($json->{"workbooks"}) or die "Error: 'workbooks' field not found for workbook '$name' in output from BigInsights Console!";
    isArray($json->{"workbooks"}) or die "Error: 'workbooks' field is not an array for workbook '$name' in output returned by BigInsights Console!";
    # child workbooks come with parent and result in more than 1 workbook being fetched
    #scalar @{$json->{"workbooks"}} != 1 and die sprintf("Error: workbook '%s' has returned 'workbooks' array of length %s instead of expected length 1\n", $name, scalar @{$json->{"workbooks"}});
    #$workbook = @{$json->{"workbooks"}}[0];
    vlog2 "writing workbook '$name' to file '$filename'";
    open ($fh, ">", $filename) or die "Failed to open file '$filename': $!\n";
    print $fh to_json($json, { pretty => 1}) or die "Failed to write to file '$filename': $!\n";
    close $fh;
    vlog2;
}

my $total_time = ceil(time - $start_time);

plural $total_time;
vlog "\nCompleted fetching and writing all workbook configurations in $total_time sec$plural\n";

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
