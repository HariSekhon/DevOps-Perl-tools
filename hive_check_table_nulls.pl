#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-05-30 10:34:27 +0100 (Thu, 30 May 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# Wrote this while on a data science course, everything on this course so far is old news to me... I guess that's good?

$DESCRIPTION = "Hive tool to check a table for NULLS";

$VERSION = "0.1.2";

my $HIVE_OPTS = "";

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
    "T|table=s" => [ \$table, "Table name to check for all nulls" ],
);

get_options();

$table   = validate_database_tablename($table, "allow_qualified");

vlog2;
set_timeout();

my $hive = "hive";
$hive .= " -S" unless $verbose;
my @output = cmd("$hive -e 'DESCRIBE $table;'");
foreach(@output){
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

my $query = "SELECT COUNT(*) from $table where " . join("=NULL OR ", @columns) . "=NULL";

my $cmd = "$hive -e '$query;' $HIVE_OPTS";
print "$cmd\n";
system("$cmd");
