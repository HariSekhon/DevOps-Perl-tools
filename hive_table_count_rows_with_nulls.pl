#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-05-30 10:34:27 +0100 (Thu, 30 May 2013)
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

# Wrote this while on a data science course, everything on this course so far is old news to me... I guess that's good?

$DESCRIPTION = "Hive tool to check a table for NULLS. Returns the number of rows containing NULLs in any field

Wrote this during Data Science course in Cloudera in 2013";

$VERSION = "0.2.1";

my $hive        = "hive";
my $hive_opts   = "";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :is/;

# set a default timeout of 10 mins and a max of 1 day
set_timeout_max(86400);
set_timeout_default(600);

my $table;
my @columns;

%options = (
    "T|table=s"   => [ \$table, "Table name to check for all nulls" ],
    "hive-path=s" => [ \$hive,  "Path to Hive command (defaults to 'hive' searching /bin:/usr/bin)" ],
);

get_options();

$table   = validate_database_tablename($table, "Hive", "allow_qualified");
$hive    = validate_program_path($hive, "hive");

vlog2;
set_timeout();

$hive_opts .= "-S" unless $verbose;
$hive_opts .= " " if $hive_opts;
my @output = cmd("$hive $hive_opts-e 'set hive.cli.print.header=false; DESCRIBE $table;'", 1);
foreach(@output){
    $_ or next;
    /^OK$/i and next;
    /^Time taken/i and next;
    /^Logging initialized/i and next;
    /^Hive history/i and next;
    /(?:^(?:FAIL|ERROR)|not exist)/i and die "HIVE $_\n";
    #my @tmp = split(/\s+/, $_);
    #my $column_name=$tmp[0];
    my $column_name=(split(/\s+/, $_))[0];
    $column_name = isDatabaseColumnName($column_name) || die "Invalid/unrecognized format for column name '$column_name' returned by Hive\n";
    push(@columns, $column_name);
}

my $query = "SELECT COUNT(*) FROM $table WHERE " . join(" IS NULL OR ", @columns) . " IS NULL";

my $cmd = "$hive $hive_opts-e '$query;'";
print "$cmd\n";
system("$cmd");
