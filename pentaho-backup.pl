#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2014-01-09 18:30:24 +0000 (Thu, 09 Jan 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Backs up the local Pentaho BA and DI Server

Ties together the full Pentaho server backup with all the embedded PostgreSQL dumps and the XML and .properties files to create a one shot backup program with error checking.

Requirements:

- Pentaho backup script utils written by Pentaho and enforces using the right versions of those as they contain very specific version bound exclusions for jar files etc
  Version is enforced by requiring that these utils be dropped in to a directory under the pentaho installation itself in a directory called 'backup_utils', such that you are responsible for ensuring you only drop in the correct version that lines up with the Pentaho installation itself

This script is in response to Pentaho not having a proper one-shot backup solution for the Pentaho server and all it's components.

Restore Procedure:

- Restore each PostgreSQL dump (assuming that you're using the embedded PostgreSQL instances otherwise restore whichever databases you have configured)
- Run \$install_dir/backup_utils/BAServerConfigAndSolutionsRestore.sh
- Run \$install_dir/backup_utils/DIServerConfigAndSolutionsRestore.sh

Used on Pentaho 5.0
";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

set_timeout_max(86400);
set_timeout_default(3600);

my $install_dir;
my $backup_dir;

my %postgres_users = (
    "jackrabbit"    =>  "jcruser",
    "quartz"        =>  "pentaho_user",
    "hibernate"     =>  "hibuser",
);

#env_creds("PostgreSQL");

%options = (
    "i|install-dir=s"   =>  [   \$install_dir,  "Pentaho installation directory" ],
    "b|backup-dir=s"    =>  [   \$backup_dir,   "Backup directory to place backups in, will create subdirectories date + timestamped under this directory" ],
    #%useroptions,
);
@usage_order = qw/install-dir backup-dir user password/;

get_options();

getpwuid($<) eq "pentaho" or die "error: you must be the 'pentaho' user to run a backup\n";

## default installation password
#$password = "password" unless $password;

$install_dir = validate_dir($install_dir, 0, "install directory");
$backup_dir  = validate_dir($backup_dir,  0, "backup directory");

go_flock_yourself();

vlog2;
my $timestamp = strftime("%F_%T", localtime);
vlog_options "backup timestamp", $timestamp;

$backup_dir .= "/$timestamp";

vlog2;
set_timeout();

( -e $backup_dir ) and die "error: backup dir '$backup_dir' already exists!\n";
( -d $backup_dir ) or mkdir($backup_dir);

chdir($backup_dir) or die "failed to change to backup directory $backup_dir to take BI and DI server backups: $!\n";

my $pg_backup_file;
foreach(qw/jackrabbit quartz hibernate/){
    $pg_backup_file = "$backup_dir/${_}$timestamp.dmp";
    tprint "Backing up PostgreSQL database '$_' to '$backup_dir'";
    cmd("'$install_dir/postgresql/bin/pg_dump' -U $postgres_users{$_} $_ > '$pg_backup_file'", 1);
    cmd("gzip -9 '$pg_backup_file'", 1);
    $pg_backup_file .= ".gz";
    cmd("md5sum '$pg_backup_file' > '${pg_backup_file}.md5'", 1);
    tprint "Finished backing up PostgreSQL database '$_'\n";
}

tprint "Backing up BA Server to $backup_dir";
cmd("$install_dir/backup_utils/BAServerConfigAndSolutionsBackup.sh '$install_dir/server/biserver-ee'", 1);
cmd("mv -v ba_backconfigandshell.zip 'ba_backconfigandshell.$timestamp.zip'", 1);
cmd("mv -v ba_backnewtomcatjars.zip  'ba_backnewtomcatjars.$timestamp.zip'",  1);
cmd("md5sum ba_backconfigandshell.$timestamp.zip > ba_backconfigandshell.$timestamp.zip.md5", 1);
cmd("md5sum ba_backnewtomcatjars.$timestamp.zip   > ba_backnewtomcatjars.$timestamp.zip.md5",  1);
tprint "Finished backing up BA Server\n";

tprint "Backing up DI Server to $backup_dir";
cmd("$install_dir/backup_utils/DIServerConfigAndSolutionsBackup.sh '$install_dir/server/data-integration-server'", 1);
cmd("mv -v di_backconfigandshell.zip 'di_backconfigandshell.$timestamp.zip'", 1);
cmd("mv -v di_backnewtomcatjars.zip  'di_backnewtomcatjars.$timestamp.zip'",  1);
cmd("md5sum di_backconfigandshell.$timestamp.zip > di_backconfigandshell.$timestamp.zip.md5", 1);
cmd("md5sum di_backnewtomcatjars.$timestamp.zip   > di_backnewtomcatjars.$timestamp.zip.md5",  1);
tprint "Finished backing up DI Server\n";

tprint "Pentaho Backup Completed Locally to $backup_dir";
