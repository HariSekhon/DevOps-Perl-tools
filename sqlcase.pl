#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-06-05 14:08:20 +0100 (Wed, 05 Jun 2013)
#
#  http://github.com/harisekhon/tools
#
#  License: see accompanying LICENSE file
#

our $DESCRIPTION = "Util to re-case SQL-like keywords from stdin or file(s), prints to standard output

Primarily written to help me clean up various SQL across Hive / Impala / MySQL / Cassandra CQL / Couchbase N1QL / Apache Drill etc. Also works with Oracle, SQL Server specific keywords and generic SQL etc.
";

$VERSION = "0.7.5";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $CONF_DIR            = ".recase";
# The SQL language files shouldn't be actively changed by users so hidden/tidied away under .recase directory
my $CONF                = "sql_keywords.conf";
my $CASSANDRA_CQL_CONF  = "cassandra_cql_keywords.conf";
my $COUCHBASE_N1QL_CONF = "couchbase_n1ql_keywords.conf";
my $DOCKER_CONF	        = "docker_keywords.conf";
my $DRILL_CONF          = "drill_keywords.conf";
my $HIVE_CONF           = "hive_keywords.conf";
my $IMPALA_CONF         = "impala_keywords.conf";
my $INFLUXDB_CONF       = "influxdb_keywords.conf";
my $MSSQL_CONF          = "mssql_keywords.conf";
my $MYSQL_CONF          = "mysql_keywords.conf";
my $NEO4J_CYPHER_CONF   = "neo4j_cypher_keywords.conf";
my $ORACLE_CONF         = "oracle_keywords.conf";
my $PGSQL_CONF          = "pgsql_keywords.conf";
my $PIG_CONF            = "pig_keywords.conf";

# Generic keywords are not hidden .dot files as they are intended to be changed by user
my $RECASE_CONF         = "recase_keywords.conf";

my $file;
my $comments;
my $cql    = 0;
my $n1ql   = 0;
my $docker = 0;
my $pig    = 0;
my $neo4j  = 0;
my $recase = 0;
my $no_upper_variables = 0;

%options = (
    "f|files=s"      => [ \$file,       "File(s) to re-case SQL from. Non-option arguments are added to the list of files" ],
    "c|comments"     => [ \$comments,   "Apply transformations even to lines that are commented out using -- or #" ],
);
@usage_order = qw/files comments/;

if($progname =~ /hive/){
    $CONF = "$CONF_DIR/$HIVE_CONF";
    $DESCRIPTION =~ s/various SQL.*/Hive SQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/Hive SQL/g;
} elsif($progname =~ /drill/){
    $CONF = "$CONF_DIR/$DRILL_CONF";
    $DESCRIPTION =~ s/various SQL.*/Apache Drill SQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/Drill SQL/g;
} elsif($progname =~ /impala/){
    $CONF = "$CONF_DIR/$IMPALA_CONF";
    $DESCRIPTION =~ s/various SQL.*/Impala SQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/Impala SQL/g;
} elsif($progname =~ /influx/){
    $CONF = "$CONF_DIR/$INFLUXDB_CONF";
    $DESCRIPTION =~ s/various SQL.*/InfluxDB QL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/InfluxDB QL/g;
} elsif($progname =~ /mysql/){
    $CONF = "$CONF_DIR/$MYSQL_CONF";
    $DESCRIPTION =~ s/various SQL.*/MySQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/MySQL SQL/g;
} elsif($progname =~ /postgres|pgsql/){
    $CONF = "$CONF_DIR/$PGSQL_CONF";
    $DESCRIPTION =~ s/various SQL.*/PostgreSQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/PostgreSQL SQL/g;
} elsif($progname =~ /mssql|microsoft/){
    $CONF = "$CONF_DIR/$MSSQL_CONF";
    $DESCRIPTION =~ s/various SQL.*/Microsoft SQL Server code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/MSSQL/g;
} elsif($progname =~ /plsql|oracle/){
    $CONF = "$CONF_DIR/$ORACLE_CONF";
    $DESCRIPTION =~ s/various SQL.*/Oracle PL\/SQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)/PL\/SQL/g;
} elsif($progname =~ /pig/){
    $CONF = "$CONF_DIR/$PIG_CONF";
    $DESCRIPTION =~ s/various SQL.*/Pig code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)?/Pig Latin/g;
    $DESCRIPTION =~ s/sql/pig/g;
    @{$options{"f|files=s"}}[1] =~ s/SQL/Pig Latin/;
    %options = ( %options,
        "no-upper-variables" => [ \$no_upper_variables, "Do not uppercase Pig dollar variables (eg. \$date => \$DATE)" ],
    );
    $pig = 1;
} elsif($progname =~ /cassandra|cql/){
    $CONF = "$CONF_DIR/$CASSANDRA_CQL_CONF";
    $DESCRIPTION =~ s/various SQL.*/Cassandra CQL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)?/Cassandra CQL/g;
    $DESCRIPTION =~ s/sql/cql/g;
    @{$options{"f|files=s"}}[1] =~ s/SQL/CQL keywords/;
    $cql = 1;
} elsif($progname =~ /couchbase|n1ql/){
    $CONF = "$CONF_DIR/$COUCHBASE_N1QL_CONF";
    $DESCRIPTION =~ s/various SQL.*/Couchbase N1QL code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)?/Couchbase N1QL/g;
    $DESCRIPTION =~ s/sql/n1ql/g;
    @{$options{"f|files=s"}}[1] =~ s/SQL/N1QL keywords/;
    $cql = 1;
} elsif($progname =~ /neo4j|cypher/){
    $CONF = "$CONF_DIR/$NEO4J_CYPHER_CONF";
    $DESCRIPTION =~ s/various SQL.*/Neo4j Cypher code and documentation/;
    $DESCRIPTION =~ s/SQL(?:-like)?/Neo4j Cypher/g;
    $DESCRIPTION =~ s/sql/neo4j_cypher/g;
    @{$options{"f|files=s"}}[1] =~ s/SQL/Neo4j Cypher keywords/;
    $neo4j = 1;
} elsif($progname eq "dockercase.pl"){
    $CONF = "$CONF_DIR/$DOCKER_CONF";
    $DESCRIPTION =~ s/various SQL.*/Dockerfiles by recasing the leading keywords/;
    $DESCRIPTION =~ s/SQL-like/Dockerfile/g;
    $DESCRIPTION =~ s/sql/docker/g;
    @{$options{"f|files=s"}}[1] =~ s/SQL/Dockerfile keywords/;
    $docker = 1;
} elsif($progname eq "recase.pl"){
    $CONF = $RECASE_CONF;
    $DESCRIPTION =~ s/various SQL.*/code and documentation via generic re-casing/;
    $DESCRIPTION =~ s/SQL/generic/g;
    $DESCRIPTION =~ s/sql/recase/g;
    @{$options{"f|files=s"}}[1] =~ s/SQL/generic keywords/;
    $recase = 1;
} else {
    $CONF = "$CONF_DIR/$CONF";
}
$DESCRIPTION .= "
Uses a regex list of keywords from '$CONF' for easy maintainance and addition of keywords";

get_options();

my @files = parse_file_option($file, "args are files");
my %keywords;
my %regexes;
my $comment_chars = qr/(?:^|\s)(?:#|--)/;

my $fh = open_file dirname(__FILE__) . "/$CONF";
sub process_regex($){
    my $regex = shift;
    $regex =~ s/\s+/\\s+/g;
    # protection against ppl leaving capturing brackets in sql_keywords.conf
    $regex =~ s/([^\\])\(([^\?])/$1\(?:$2/g;
    # wraps regex in (?:XISM: ) so don't replace the regex
    validate_regex($regex);
    return $regex;
}
foreach(<$fh>){
    chomp;
    s/(?:#|--).*//;
    $_ = trim($_);
    /^\s*$/ and next;
    my $regex = $_;
    # store case sensitive replacements separately, so we replace as-is
    # this won't work due to \w, \s, \d etc
    if($regex =~ /[a-z]/ or $docker){
        $regex = process_regex($regex);
        $keywords{$regex} = 1;
    } else {
        $regex = process_regex($regex);
        $regexes{$regex} = 1;
    }
}

#if($pig and $no_upper_variables == 0){
#    $keywords{'\$\w+'} = 1;
#}

sub recase ($;$) {
    my $string = shift;
    my $literal_replacement = shift;
    my $captured_comments = undef;
    #$string =~ /(?:SELECT|SHOW|ALTER|DROP|TRUNCATE|GRANT|FLUSH)/ or return $string;
    unless($comments){
        if($string =~ s/(${comment_chars}.*$)//){
            $captured_comments = $1;
        }
    }
    if($string){
        # cannot simply use word boundary here since NULL would match /dev/null
        # removed \. because of WITH PARAMETERS (credentials.file=file.txt)
        # don't uppercase group.domain => GROUP.domain
        # removed colon :  because of "jdbc:oracle:..."
        my $sep = '\s|=|\(|\)|\[|\]|,|;|\n|\r\n|\"|#|--|' . "'";
	if($docker){
            foreach my $keyword_regex (sort keys %keywords){
                $string =~ s/^(\s*)$keyword_regex(\s)/$1$keyword_regex$2/gi and vlog3 "replaced Docker keyword $keyword_regex";
            }
        } else {
            # do camelCase org.apache.hcatalog.pig.HCatLoader()
            # XXX: why does this not work on "-- # alter " but it works on "-- #alter " or "-- #  alter "
            foreach my $keyword_regex (sort keys %keywords){
                $string =~ s/(^|$sep)(\Q$keyword_regex\E)($sep|$)/$1$keyword_regex$3/gi and vlog3 "replaced keyword $keyword_regex";
            }
            foreach my $keyword_regex (sort keys %regexes){
                if($string =~ /(^|$sep)($keyword_regex)($sep|$)/gi){
                    my $uc_keyword;
                    if($keyword_regex =~ /[a-z]/){
                        # XXX: special rule to uppercase Pig variables
                        if($pig and $no_upper_variables == 0 and $keyword_regex eq '\$\w+'){
                            $uc_keyword = uc $2;
                        } else {
                            # this would have included regex chars instead of just the case replacements
                            #$uc_keyword = $keyword;
                            $uc_keyword = $2;
                            foreach(split(/[^A-Za-z_]/, $keyword_regex)){
                                $uc_keyword =~ s/(^|$sep)($_)($sep|$)/$1$_$3/gi and vlog3 "replaced keyword $_ with uppercase";
                            }
                        }
                    } else {
                        $uc_keyword = uc $2;
                    }
                    # have to redefine comment chars here because variable length negative lookbehind isn't implemented
                    $string =~ s/(?<!\s#)(?<!\s--)(^|$sep)$keyword_regex($sep|$)/$1$uc_keyword$2/gi and vlog3 "replaced keyword '$uc_keyword'";
                }
            }
        }
    }
    if($captured_comments){
        chomp $string;
        $string .= $captured_comments . "\n";
    }
    return $string;
}

if(@files){
    foreach my $file (@files){
        open(my $fh, $file) or die "Failed to open file '$file': $!\n";
        while(<$fh>){ print recase($_) }
    }
} else {
    while(<STDIN>){ print recase($_) }
}
