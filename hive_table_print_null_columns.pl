#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 27/6/2014
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

$DESCRIPTION = "Hive tool to print any columns from a table that contain entirely null fields

Written to find and clean data before importing to 0xdata H2O since there is a Java bug relating to entirely null columns

See Also:

Newer versions for HiveServer2 and Impala in DevOps Python tools repo:

https://github.com/harisekhon/devops-python-tools
";

$VERSION = "0.2.2";

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

$table   = validate_database_tablename($table, "Hive", "allow_qualified");
$hive    = validate_program_path($hive, "hive");

vlog2;
set_timeout();

sub hive_check_output_line($){
    my $line = shift;
    if($line =~
    /^(?:
    \s*$  |
    OK$   |
    Time\staken |
    Logging\sinitialized |
    Hive\shistory
    )/ix){
        return 1;
    }
    /(?:^(?:FAIL|ERROR)|not exist)/i and die "HIVE $_\n";
    return 0;
}

$hive_opts .= "-S" unless $verbose;
$hive_opts .= " " if $hive_opts;
my @output = cmd("$hive $hive_opts-e 'set hive.cli.print.header=false; DESCRIBE $table;'", 1);
my $column_name;
foreach(@output){
    hive_check_output_line($_) and next;
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
    #                count number of NULLs    vs total  => output 1 to indicate all NULLs, else 0
    $sum_part .= "IF(SUM(IF($_ IS NULL, 1, 0)) = COUNT(*), 1, 0) as $_, ";
}
$sum_part =~ s/, $//;
$query = "SELECT $sum_part FROM $table WHERE " . join(" IS NULL OR ", @columns) . " IS NULL";

my $cmd = "$hive $hive_opts-e 'set hive.cli.print.header=false; $query';";
@output = cmd("$cmd", 1);
my @null_cols;
foreach(@output){
    hive_check_output_line($_) and next;
    @null_cols = split(/\s+/);
    last;
}
my $num_null_cols = 0;
foreach(@null_cols){
    $_ and $num_null_cols++;
}
if($num_null_cols){
    print "Columns with all NULLs:\n\n";
    foreach(my $i=0; $i < scalar @null_cols; $i++){
        $null_cols[$i] and print $columns[$i] . "\n";
    }
} else {
    print "No columns with all NULLs\n";
}
