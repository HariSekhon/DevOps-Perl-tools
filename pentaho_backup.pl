#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2014-01-09 18:30:24 +0000 (Thu, 09 Jan 2014)
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

$DESCRIPTION = "Backs up the local Pentaho BA and DI Server

Ties together the full Pentaho server backup with all the embedded PostgreSQL dumps and the XML and .properties files to create a one shot backup program with error checking.

Unlike the recommendation to 'shut down the Pentaho server and backup the whole server or whole /opt/pentaho application directory', this method does not require switching off the Pentaho server components to back it up.

Requirements:

- Pentaho backup script utils written by Pentaho and enforces using the right versions of those as they contain very specific version bound exclusions for jar files etc
  - Version is enforced by requiring that these utils be dropped in to a directory under the pentaho installation itself in a directory called 'backup_utils', such that you are responsible for ensuring you only drop in the correct version that lines up with the Pentaho installation itself
  - Download UpgradeUtility-vX.Y.Z.zip from the Pentaho Support Portal Upgrade instructions from your specific version, unzip and move and rename the '_nix' directory to 'backup_utils' under the pentaho top level installation directory
  - Please be aware you may hit minor quoting bugs in these scripts and require minor edits to get them working:
    - https://support.pentaho.com/entries/38570876-Error-after-running-BAServerConfigAndSolutionsBackup-sh
    - http://jira.pentaho.com/browse/BISERVER-10828#comment-167926
    - http://jira.pentaho.com/browse/PDI-11241
- Only supports local backups due to the dependence on the Pentaho version specific local backup scripts

- PostgreSQL credentials:
  - Environment variables can be used for PostgreSQL credentials to the embedded databases:
    - \$<database_name>_PGUSER if found in environment is used where <database_name> is one of: jackrabbit, di_jackrabbit, quartz, di_quartz, hibernate, di_hibernate
      - PostgreSQL user defaults to jcr_user, pentaho_user and hibuser respectively otherwise
    - \$PGPASSWORD can be defined if all the databases share the same password
      - \$<database_name>_PGPASSWORD overrides this on a per database basis
      - defaults to 'password' if neither \$PGPASSWORD nor \$<database_name>_PGPASSWORD are set

This script is in response to Pentaho not having a proper one-shot backup solution for the Pentaho server and all it's components.

Restore Procedure:

- Restore each PostgreSQL dump (assuming that you're using the embedded PostgreSQL instances otherwise restore whichever databases you have configured)
- Run \$install_dir/backup_utils/BAServerConfigAndSolutionsRestore.sh
- Run \$install_dir/backup_utils/DIServerConfigAndSolutionsRestore.sh

Used on Pentaho 5.0
";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use POSIX;

set_timeout_max(86400);
set_timeout_default(3600);

my $install_dir;
my $backup_dir;
my $ba_server;
my $di_server;
my $backup_ba_di;
my $no_postgres;

#   database        =>  user/password
# default postgres users
my %postgres_users = (
    "jackrabbit"    =>  "jcr_user",
    "quartz"        =>  "pentaho_user",
    "hibernate"     =>  "hibuser",
);
foreach(keys %postgres_users){
    if($ENV{uc "${_}_PGUSER"}){
        $postgres_users{$_} = $ENV{uc "${_}_PGUSER"};
    }
};

# This is the default password for the embedded Pentaho postgres databases
$ENV{"PGPASSWORD"} = "password" unless $ENV{"PGPASSWORD"};

#env_creds("PostgreSQL");

%options = (
    "i|install-dir=s"   =>  [ \$install_dir,  "Pentaho installation directory" ],
    "b|backup-dir=s"    =>  [ \$backup_dir,   "Backup directory to place backups in, will create subdirectories date + timestamped under this directory" ],
    "ba-server"         =>  [ \$ba_server,    "Only back up the BA Server (default backs up both BA and DI server)" ],
    "di-server"         =>  [ \$di_server,    "Only back up the DI Server (default backs up both BA and DI server)" ],
    "no-postgres"       =>  [ \$no_postgres,  "Don't back up embedded PostgreSQL DBs. Specify if using custom databases backing Pentaho - back up those yourself" ],
);
@usage_order = qw/install-dir backup-dir ba-server di-server no-postgres/;

get_options();

getpwuid($<) eq "pentaho" or die "error: you must be the 'pentaho' user to run a backup\n";

$install_dir = validate_dir($install_dir, "install directory");
$backup_dir  = validate_dir($backup_dir,  "backup directory");
vlog_option "ba-server", "true" if $ba_server;
vlog_option "di-server", "true" if $di_server;
vlog_option "no-postgres", "true" if $no_postgres;
if(not $ba_server and not $di_server){
    $backup_ba_di = 1;
}

go_flock_yourself();

vlog2;
my $timestamp = strftime("%F_%T", localtime);
vlog_option "backup timestamp", $timestamp;

$backup_dir .= "/$timestamp";

vlog2;
set_timeout();

( -e $backup_dir ) and die "error: backup dir '$backup_dir' already exists!\n";
( -d $backup_dir ) or mkdir($backup_dir);

chdir($backup_dir) or die "failed to change to backup directory $backup_dir to take BI and DI server backups: $!\n";

sub backup_dbs(;$){
    my $di = shift || "";
    $di = "di_" if $di;
    unless($no_postgres){
        my $db;
        my $pg_backup_file;
        my $pg_user = $ENV{"PGUSER"};
        foreach(qw/jackrabbit quartz hibernate/){
            $db = "$di$_";
            $pg_backup_file = "$backup_dir/${db}_$timestamp.sql";
            tprint "Backing up PostgreSQL database '$db' to '$backup_dir'";
            if($ENV{uc "${db}_PGUSER"}){
                $ENV{"PGUSER"} = $ENV{uc "${db}_PGUSER"};
            } elsif($pg_user){
                $ENV{"PGUSER"} = $pg_user;
            } else {
                $ENV{"PGUSER"} = $postgres_users{$_};
            }
            $ENV{"PGPASSWORD"} = $ENV{uc "${db}_PGPASSWORD"} if $ENV{uc "${db}_PGPASSWORD"};
            tprint "connecting to database $db with user $ENV{PGUSER}";
            cmd("$install_dir/postgresql/bin/pg_dump $_ -f '$pg_backup_file'", 1);
            cmd("gzip -9 '$pg_backup_file'", 1);
            $pg_backup_file .= ".gz";
            cmd("md5sum '$pg_backup_file' > '${pg_backup_file}.md5'", 1);
            tprint "Finished backing up PostgreSQL database '$db'\n";
        }
    }
}

if($ba_server or $backup_ba_di){
    tprint "Backing up BA Server to $backup_dir";
    backup_dbs();
    cmd("rm -vf ~/ba_backconfigandshell.zip ~/ba_backnewtomcatjars.zip", 1);
    cmd("$install_dir/backup_utils/BAServerConfigAndSolutionsBackup.sh '$install_dir/server/biserver-ee'", 1);
    cmd("mv -v ~/ba_backconfigandshell.zip 'ba_backconfigandshell.$timestamp.zip'", 1);
    cmd("mv -v ~/ba_backnewtomcatjars.zip  'ba_backnewtomcatjars.$timestamp.zip'",  1);
    cmd("md5sum ba_backconfigandshell.$timestamp.zip > ba_backconfigandshell.$timestamp.zip.md5", 1);
    cmd("md5sum ba_backnewtomcatjars.$timestamp.zip   > ba_backnewtomcatjars.$timestamp.zip.md5",  1);
    tprint "Finished backing up BA Server\n";
}

if($di_server or $backup_ba_di){
    tprint "Backing up DI Server to $backup_dir";
    backup_dbs("di");
    cmd("rm -vf ~/di_backconfigandshell.zip ~/di_backnewtomcatjars.zip", 1);
    cmd("$install_dir/backup_utils/DIServerConfigAndSolutionsBackup.sh '$install_dir/server/data-integration-server'", 1);
    cmd("mv -v ~/di_backconfigandshell.zip 'di_backconfigandshell.$timestamp.zip'", 1);
    cmd("mv -v ~/di_backnewtomcatjars.zip  'di_backnewtomcatjars.$timestamp.zip'",  1);
    cmd("md5sum di_backconfigandshell.$timestamp.zip > di_backconfigandshell.$timestamp.zip.md5", 1);
    cmd("md5sum di_backnewtomcatjars.$timestamp.zip   > di_backnewtomcatjars.$timestamp.zip.md5",  1);
    tprint "Finished backing up DI Server\n";
}

tprint "Pentaho Backup Completed Locally to $backup_dir";
