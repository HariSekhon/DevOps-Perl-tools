#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-05-30 10:34:27 +0100 (Thu, 30 May 2013)
#  Copied for repurpose 27/6/2014
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Hive tool to print any columns from a table that contain entirely null fields

Written to find and clean data before importing to 0xdata H2O since there is a Java bug relating to entirely null columns";

$VERSION = "0.1.0";

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
    "T|table=s"   => [ \$table, "Table name to check for all entirely null columns" ],
    "hive-path=s" => [ \$hive,  "Path to Hive command (defaults to 'hive' searching /bin:/usr/bin)" ],
);

get_options();

$table   = validate_database_tablename($table, "allow_qualified");
$hive    = validate_program_path($hive, "hive");

vlog2;
set_timeout();

$hive_opts .= "-S" unless $verbose;
$hive_opts .= " " if $hive_opts;
my @output = cmd("$hive $hive_opts-e 'DESCRIBE $table;'", 1);
my $column_name;
foreach(@output){
    $_ or next;
    /^OK$/i and next;
    /^Time taken/i and next;
    /^Logging initialized/i and next;
    /^Hive history/i and next;
    /(?:^(?:FAIL|ERROR)|not exist)/i and die "HIVE $_\n";
    #my @tmp = split(/\s+/, $_);
    #my $column_name=$tmp[0];
    $column_name = (split(/\s+/, $_))[0];
    $column_name = ( isDatabaseColumnName($column_name) || die "Invalid/unrecognized format for column name '$column_name' returned by Hive\n" );
    push(@columns, $column_name);
}

my $query;
my $sum_part = "";
foreach(@columns){
    #$sum_part .= "SUM(IF($_ IS NULL, 1, 0)) as $_, ";
    $sum_part .= "IF(SUM(IF($_ IS NULL, 1, 0)) > 0, TRUE, FALSE) as $_, ";
}
$sum_part =~ s/, $//;
$query = "SELECT $sum_part FROM $table WHERE " . join(" IS NULL OR ", @columns) . " IS NULL";

my $cmd = "$hive $hive_opts-e 'set hive.cli.print.header=true; $query';";
print "$cmd\n";
system("$cmd");
