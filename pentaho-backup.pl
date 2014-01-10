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
- Only supports local backups due to the dependence on the Pentaho version specific local backup scripts

- PostgreSQL credentials:
  - Environment variables can be used for PostgreSQL credentials to the embedded databases:
    - \$<database_name>_PGUSER if found in environment is used where <database_name> is jackrabbit, quartz or hibernate.
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

$VERSION = "0.1";

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
    "no-postgres"       =>  [ \$no_postgres,  "Don't back up embedded PostgreSQL DBs. Specify if using customer databases backing Pentaho - back up those yourself" ],
);
@usage_order = qw/install-dir backup-dir ba-server di-server no-postgres/;

get_options();

getpwuid($<) eq "pentaho" or die "error: you must be the 'pentaho' user to run a backup\n";

$install_dir = validate_dir($install_dir, 0, "install directory");
$backup_dir  = validate_dir($backup_dir,  0, "backup directory");
vlog_options "ba-server", "true" if $ba_server;
vlog_options "di-server", "true" if $di_server;
vlog_options "no-postgres", "true" if $no_postgres;
if(not $ba_server and not $di_server){
    $backup_ba_di = 1;
}

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

unless($no_postgres){
    my $pg_backup_file;
    my $pg_user = $ENV{"PGUSER"};
    foreach(qw/jackrabbit quartz hibernate/){
        $pg_backup_file = "$backup_dir/${_}_$timestamp.sql";
        tprint "Backing up PostgreSQL database '$_' to '$backup_dir'";
        if($ENV{uc "${_}_PGUSER"}){
            $ENV{"PGUSER"} = $ENV{uc "${_}_PGUSER"};
        } elsif($pg_user){
            $ENV{"PGUSER"} = $pg_user;
        } else {
            $ENV{"PGUSER"} = $postgres_users{$_};
        }
        $ENV{"PGPASSWORD"} = $ENV{uc "${_}_PGPASSWORD"} if $ENV{uc "${_}_PGPASSWORD"};
        tprint "connecting to database $_ with user $ENV{PGUSER}";
        cmd("$install_dir/postgresql/bin/pg_dump $_ -f '$pg_backup_file'", 1);
        cmd("gzip -9 '$pg_backup_file'", 1);
        $pg_backup_file .= ".gz";
        cmd("md5sum '$pg_backup_file' > '${pg_backup_file}.md5'", 1);
        tprint "Finished backing up PostgreSQL database '$_'\n";
    }
}


if($ba_server or $backup_ba_di){
    tprint "Backing up BA Server to $backup_dir";
    cmd("rm -v ~/ba_backconfigandshell.zip ~/ba_backnewtomcatjars.zip", 1);
    cmd("$install_dir/backup_utils/BAServerConfigAndSolutionsBackup.sh '$install_dir/server/biserver-ee'", 1);
    cmd("mv -v ~/ba_backconfigandshell.zip 'ba_backconfigandshell.$timestamp.zip'", 1);
    cmd("mv -v ~/ba_backnewtomcatjars.zip  'ba_backnewtomcatjars.$timestamp.zip'",  1);
    cmd("md5sum ba_backconfigandshell.$timestamp.zip > ba_backconfigandshell.$timestamp.zip.md5", 1);
    cmd("md5sum ba_backnewtomcatjars.$timestamp.zip   > ba_backnewtomcatjars.$timestamp.zip.md5",  1);
    tprint "Finished backing up BA Server\n";
}

if($di_server or $backup_ba_di){
    tprint "Backing up DI Server to $backup_dir";
    cmd("rm -v ~/di_backconfigandshell.zip ~/di_backnewtomcatjars.zip", 1);
    cmd("$install_dir/backup_utils/DIServerConfigAndSolutionsBackup.sh '$install_dir/server/data-integration-server'", 1);
    cmd("mv -v ~/di_backconfigandshell.zip 'di_backconfigandshell.$timestamp.zip'", 1);
    cmd("mv -v ~/di_backnewtomcatjars.zip  'di_backnewtomcatjars.$timestamp.zip'",  1);
    cmd("md5sum di_backconfigandshell.$timestamp.zip > di_backconfigandshell.$timestamp.zip.md5", 1);
    cmd("md5sum di_backnewtomcatjars.$timestamp.zip   > di_backnewtomcatjars.$timestamp.zip.md5",  1);
    tprint "Finished backing up DI Server\n";
}

tprint "Pentaho Backup Completed Locally to $backup_dir";
