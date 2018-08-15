#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-05-23 09:19:57 +0100 (Sat, 23 May 2015)
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

$DESCRIPTION = "Tool to automate indexing from an arbitrary Hive table to an Elasticsearch index, with support for Kerberos and large scale partitioned tables.

This is a completely new rewrite to unify a bunch of other scripts I was using for a selection of Hive tables in a more generically reusable way.

You should supply the full list of Elasticsearch nodes for --nodes, otherwise defaults to localhost:9200.

Kerberos is supported but you must generate a TGT before running this program and the ticket must be renewable. This helps when looping through Hive table partitions as it will refresh the TGT to stop it expiring before each partition, which is especially important for high scale partitioned table indexing which can take days for billions of records if iterating on lots of partitions.

The programs 'hive' and 'kinit' are assummed to be in the base PATH $ENV{PATH}, otherwise you must set them at the top of this program.

Creates hive table of same name as each indexed table with '_elasticsearch' suffixed to it. Deletes and re-creates that _elasticsearch table each time to ensure correct data is sent and aligned with Elasiticsearch.

For high scale multi-billion row partitioned Hive tables, I've found it very impractical to try to index it all in one go as any interruption in such long running jobs means you have to start the jobs from the beginning instead of the part-way resume behaviour which partitioning naturally gives, so I recommend using partitions with --suffix to create an index-per-partition and --alias those indicies back under a global index alias for conveniently querying via one name.

For inline data transformations set up a Hive view and specify --view. If the view is based on a partitioned table(s) then you must specify --table to get the partitions to iterate over if not specifying --partition-key and --partition-value. You typically want to use a view to generate the id field or correctly format the date field for Elasticsearch. You can also use views to handle nested partitions or other scenarios not directly catered to.

Libraries Required:

ES Hadoop - https://www.elastic.co/downloads/hadoop

You need the 'elasticsearch-hadoop-hive.jar' from the link above as well as the Apache 'commons-httpclient.jar' (which should be supplied inside your Hadoop distribution). For convenience this program will attempt to automatically find the jars in the following locations:

1. jar files adjacent to this program in the same directory
2. jar files in the current working directory
3. jar files in your \$HOME directory
4. the standard distribution paths on Hortonworks HDP, Cloudera CDH (parcels) as well as /usr/lib/hive*/lib and /usr/lib/hadoop*/lib for legacy. This is mostly tested on the standard Hortonworks HDP though
5. elasticsearch-hadoop-hive.jar / elasticsearch-hadoop.jar in straight zip unpacked directories found in any of the above locations

Caveats: the Hive->Elasticsearch indexing integration can be extremely fiddly and result in not indexing mismatched field types etc, so editing this process which I've spent a long time on is at your own peril. If you do make any modifications/improvements please submit a patch in the form of a github pull request to https://github.com/harisekhon/devops-perl-tools (which is part of my license in providing this to you for free).

Tested on Hortonworks HDP 2.2 using Hive 0.14 => Elasticsearch 1.2.1, 1.4.1, 1.5.2 using ES Hadoop 2.1.0 (I recommend Beta4 onwards as there was some job xml character bug prior to that in Beta3, see https://github.com/elastic/elasticsearch-hadoop/issues/359)";

$VERSION = "0.8.9";

# XXX: Beeline CLI doesn't have ability to add local jars yet as of 0.14, see https://issues.apache.org/jira/browse/HIVE-9302
#
# This would be needed for any port to Beeline otherwise the jars are assumed to be on the HiveServer2, and then that would only work from Hive 1.2, not porting this any time soon :-/

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex :time/;
use HariSekhon::Elasticsearch;
use Cwd 'abs_path';
use Search::Elasticsearch;
# see explanation further down why not using TT
#use Template;

########################
#
# Your settings go here
#
# You can hard code your JAR paths here if needed
my $elasticsearch_hadoop_hive_jar = "";
my $commons_httpclient_jar        = "";

# Hardcode the paths to your hive and kinit commands if they're not in the basic $PATH (which gets scrubbed from the environment for security taint mode to just the system paths /bin:/usr/bin/:/sbin:/usr/sbin:/usr/local/bin:/usr/local/sbin)
# In case you're on Hortonworks and using Tez, I find that MapReduce is more robust, similar in terms of performance at high scale and gives better reporting in the Yarn Resource Manager as to whether a job succeeded or failed
my $hive  = 'hive';
#my $hive  = 'hive --hiveconf hive.execution.engine=mr';
# Don't wait for a Tez session just to get partition and column info as this can block and we only need Metastore access
my $hive_desc_opts="--hiveconf hive.execution.engine=mr";
# if you must use Tez you can also put use -S switch for silent mode if you are tee-ing this to a log file and don't want all that interactive terminal progress bars cluttering up and enlarging your logs since they don't come out properly when written to a log file anyway
# $hive .= ' -S';
my $kinit = 'kinit';

# search these locations for elasticsearch and http commons jars
my @jar_search_paths = qw{
    .
    /usr/hdp/current/hive-client/lib
    /usr/hdp/current/hadoop-client/lib
    /usr/hdp/current/hadoop-client/client
    /opt/cloudera/parcels/CDH/lib/hive/lib
    /opt/cloudera/parcels/CDH/lib/hadoop/client
    /opt/cloudera/parcels/CDH/lib/hadoop/lib
    /opt/cloudera/parcels/CDH/jars
    /opt/cloudera/parcels/CDH/lib
    /usr/lib/hive*/lib
    /usr/lib/hadoop*/lib
};
splice @jar_search_paths, 0, 0, dirname(__FILE__);
splice @jar_search_paths, 2, 0, $ENV{'HOME'};

my $es_ignore_errors = [ 400, 404, 500 ];

########################

# bulk indexing billions of documents can take hours
set_timeout_max(86400 * 7);
set_timeout_default(86400 * 3);

# make it easier to just | tee some.log as it's easy to forget to 2>&1 and then not have the log info to look back on
open STDERR, ">&STDOUT";
autoflush();

$verbose = 1;

# these are evaluated in regex brackets [ ]
my $valid_partition_key_chars   = "A-Za-z0-9_-";
my $valid_partition_value_chars = "A-Za-z0-9_-";

my $db = "default";
my $table;
my $view;
my $columns;
my $column_file;
my $alias;
my $delete_on_failure;
my $no_task_retries;
my $optimize;
my $partition_key;
my $partition_values;
my $queue = "default";
my $recreate_index;
my $skip_existing;
my $stop_on_failure;
my $shards_default = 5;
my $shards = $shards_default;
my $suffix_index;

# default if not specified, for those being lazy with development (ie me) and people who have colocated Elasticsearch+Hadoop clusters. Everyone else doing proper high scale remote Elasticsearch clusters will need to specify nodes
$nodes = "localhost:9200";

%options = (
    %nodeoptions,
    "d|db|database=s"       =>  [ \$db,                 "Hive database to work inside (defaults to the 'default' database)" ],
    "T|table=s"             =>  [ \$table,              "Hive table to index to Elasticsearch (required to detect/iterate over Hive partitions). May be qualified with the database name" ],
    "E|view=s"              =>  [ \$view,               "Hive view to actually query the data from (to allow for live transforms for generated IDs or correct date format for Elasticsearch). May be qualified with the database name" ],
    "C|columns=s"           =>  [ \$columns,            "Hive table columns in the given table to index to Elasticsearch, comma separated (defaults to indexing all columns)" ],
    "F|column-file=s"       =>  [ \$column_file,        "File containing Hive column names to index, one per line (use when you have a lot of columns and don't want massive command lines)" ],
    "p|partition-key=s"     =>  [ \$partition_key,      "Hive table partition. Optional but recommended for high scale and to split Elasticsearch indexing jobs in to more easily repeatable units in case of failures" ],
    "u|partition-values=s"  => [ \$partition_values,    "Hive table partition value(s), can be comma separated to index multiple partitions. Optional, but requires --parition-key if specified" ],
    %elasticsearch_index,
    %elasticsearch_type,
    "s|shards=s"            => [ \$shards,              "Number of shards to create for new index, must be a positive integer (default: $shards_default)" ],
    "suffix-index"          => [ \$suffix_index,        "Suffix partition value to the index name (consider combining with --alias). Requires a Hive partitioned table where --partition-key/--partition-values are specified or all partitions are auto-determined and processed using --table" ],
    "a|alias=s"             => [ \$alias,               "Elasticsearch alias to add the index to after it's finished indexing. Optional" ],
    "o|optimize"            => [ \$optimize,            "Optimize Elasticsearch index after indexing and aliasing finishes. Optional" ],
    "q|queue=s"             => [ \$queue,               "Hadoop scheduler queue to run the Hive job in (use this to throttle and not overload Elasticsearch and trigger indexing job failures, default: $queue)" ],
    "recreate-index"        => [ \$recreate_index,      "Deletes + recreates the Elasticsearch index if already existing to truncate and ensure it has the correct settings (eg. number of --shards). Use when using autogenerated keys to avoid duplicates" ],
    "delete-on-failure"     => [ \$delete_on_failure,   "Delete Elasticsearch index if the indexing job fails, useful when combined with --skip-existing to be able to re-run safely over and over to fill in new or missing partitions that haven't been indexed yet" ],
    "skip-existing"         => [ \$skip_existing,       "Skip job if the Elasticsearch index already exists (useful with --delete-on-failure to give safe retry semantics for indexing only missing Hive partitions that did not successfully complete on previous runs)" ],
    "no-task-retries"       => [ \$no_task_retries,     "Fails job if any task fails to prevent duplicates being introduced if using autogenerated IDs as it be may be better to combine with --recreate-index or --delete-on-failure to recreate index without duplicates in that case" ],
    "stop-on-failure"       => [ \$stop_on_failure,     "Stop processing successive Hive partitions if a partition fails to index to Elasticsearch (default is to wait 10 mins after index failure before attempting the next one to iterate over the rest of the partitions in case the error is transitory, such as a temporary networking outage, in which case you may be able to get some or all of the rest of the partitions indexed when the network/cluster(s) recover and just go back and fill in the missing days, maximizing bulk indexing time for overnight jobs)" ],
);
@usage_order = qw/node nodes port db database table view columns column-file partition-key partition-values index type shards alias optimize queue recreate-index delete-on-failure skip-existing no-task-retries stop-on-failure/;

get_options();

my @nodes = validate_nodeport_list($nodes);
$host     = $nodes[0];
$port     = validate_port($port);
$db       = validate_database($db, "Hive");
$table    = validate_database_tablename($table, "Hive", "allow qualified") if defined($table);
$view     = validate_database_viewname($view, "Hive", "allow qualified") if defined($view);
# Fix naming throughout code depending on if table/view are fully qualified or not
my $tabledb = "$db.";
my $viewdb  = "$db.";
if($table and $table =~ /\./){
    $tabledb = "";
}
if($view and $view =~ /\./){
    $viewdb = "";
}
$table or $view or usage "must specify a table or a view";
my @columns;
($columns and $column_file) and usage "--columns and --column-file are mutually exclusive!";
if($column_file){
    my $fh = open_file($column_file);
    my @column_from_file;
    while(<$fh>){
        chomp;
        s/#.*//;
        next if /^\s*$/;
        push(@column_from_file, $_);
        $columns = join(",", @column_from_file);
    }
}
if($columns){
    foreach(split(/\s*,\s*/, $columns)){
        $_ = validate_database_columnname($_);
        push(@columns, $_);
    }
    @columns = uniq_array2 @columns;
    vlog_option "deduped columns to index", "@columns";
}
$index  = validate_elasticsearch_index($index);
$type or $type = $index;
$type   = validate_elasticsearch_type($type);
$alias  = validate_elasticsearch_alias($alias) if defined($alias);
$shards = validate_int($shards, "shards", 1, 1000);
$queue  = validate_alnum($queue, "queue");
if($alias eq $index and not $suffix_index){
    die "cannot specify --alias with same name as --index when --suffix-index is not used!\n";
}
if((defined($partition_key) and not defined($partition_values)) or (defined($partition_values) and not defined($partition_key))){
    usage "if using partitions must specify both --partition-key and --partition-value";
}
#$partition_key = validate_alnum($partition_key, "partition key") if $partition_key;
$partition_key = validate_chars($partition_key, "partition key", $valid_partition_key_chars) if $partition_key;
my @partitions;
if($partition_values){
    foreach(split(/\s*,\s*/, $partition_values)){
        $_ = validate_chars($_, "partition value", $valid_partition_value_chars);
        push(@partitions, "$partition_key=$_");
    }
    @partitions = uniq_array2 @partitions;
    vlog_option "deduped partitions to index", "@partitions";
}
($skip_existing and $recreate_index) and usage "--skip-existing and --recreate-index are mutually exclusive!";
vlog_option_bool "suffix-index",      $suffix_index;
vlog_option_bool "optimize",          $optimize;
vlog_option_bool "recreate-index",    $recreate_index;
vlog_option_bool "delete-on-failure", $delete_on_failure;
vlog_option_bool "skip-existing",     $skip_existing;
vlog_option_bool "no-task-retries",   $no_task_retries;
vlog_option_bool "stop-on-failure",   $stop_on_failure;
my $es_ignore_errors_orig = $es_ignore_errors;
$es_ignore_errors = [] if $stop_on_failure;

my $es_nodes = join(",", @nodes);
my $es_port  = $port;

my $node_num = scalar @nodes;
foreach(my $i=0; $i < $node_num; $i++){
    $nodes[$i] =~ /:/ or $nodes[$i] .= ":$port";
}

vlog2;
set_timeout();

$status = "OK";

# Safer to not template because:
# - writing a templated HQL file would leave a race condition
# - passing into code via system() has taint security implications
#my $hql = dirname(__FILE__) . "/hive-to-elasticsearch.hql";
#my $template_file = "$hql.tt2";
#my $fh = open_file($template_file);
#my %hql_template_vars = (
#);
#my $hql_template = <$fh>;
#close $fh;
#$hql_template or die "Failed to read HQL template file '$template_file'";
#my $tt = Template->new or die $Template::ERROR, "\n";

my $table_or_view = ( $view ? "view" : "table" );
my $src = $view ? "$viewdb$view" : "$tabledb$table";

vlog "# " . "=" x 76 . " #";
# need to leave $table intact here still since if it exists later we will do partition checks
vlog "#  Hive database '$db' $table_or_view '$src' => Elasticsearch";
#plural @nodes;
#vlog2 "(node$plural: '$es_nodes')";
vlog "# " . "=" x 76 . " #\n";

vlogt "Starting indexing run";
vlogt "instantiating Elasticsearch cluster client";
my $es = Search::Elasticsearch->new(
    'nodes'    => [ @nodes ],
    #'cxn_pool' => 'Sniff',
    #'trace_to' => 'Stderr'
);

sub create_index($){
    my $index = shift;
    plural $shards;
    vlogt "creating index '$index' with $shards shard$plural, no replicas and no refresh in order to maximize bulk indexing performance";
#    my $response = curl_elasticsearch_raw "/$index", "PUT", "
#index:
#    number_of_shards: $shards
#    number_of_replicas: 0
#    refresh_interval: -1
#"
#    my $response = curl_elasticsearch_raw "/$index", "PUT", "
#    \"settings\": {
#        \"index\": {
#            \"number_of_shards\":   $shards,
#            \"number_of_replicas\": 0,
#            \"refresh_interval\":  -1
#        }
#    }
#    "
    my $result = $es->indices->create(
        'index'  => $index,
        'ignore' => $es_ignore_errors, # worst case we'll create a default index instead, better than nothing for overnight jobs, can always re-index later
        'body'   => "{
            \"settings\": {
                \"index\": {
                    \"number_of_shards\":   $shards,
                    \"number_of_replicas\": 0,
                    \"refresh_interval\":  -1
                }
            }
        }"
    );
    return $result;
}

sub exit_if_controlc($){
    my $exit_code = shift;
    # user Control-C'd this program, don't iterate on further indices
    if($exit_code == 33280){
        print "Control-C detected, exiting without attempting further indices";
        exit $ERRORS{"UNKNOWN"};
    }
}

my $partitions_found;
my @partitions_found;
my @columns_found;
my $create_columns = "";

sub get_columns(){
    my $table = $table;
    $table = $view if $view;
    vlogt "checking columns in $table_or_view $src (this may take a minute)";
    # or try hive -S -e 'SET hive.cli.print.header=true; SELECT * FROM $src LIMIT 0'
    my $output = `$hive -S $hive_desc_opts --hiveconf hive.session.id=ES-describe -e 'use $db; describe $table' 2>/dev/null`;
    exit_if_controlc($?);
    my @output = split(/\n/, $output);
    my %columns;
    foreach(@output){
        # bit hackish but quick to do, take lines which look like "^column_name<space>column_type$" - doesn't support
        # This and the uniq_array2 on @columns_found prevent the partition by field being interpreted as another column which breaks the generated HQL
                # Tables                    # Views
        last if /Partition Information/i or /# Detailed Table Information/;
        #            NAME           TYPE (eg. string, double, boolean)
        if(/^\s*($column_regex)\s+([A-Za-z]+)\s*$/){
            $columns{$1} = $2;
            push(@columns_found, $1);
        }
    }
    die "\nfound no columns for $src - does $table_or_view exist?\n" unless @columns_found;
    @columns_found = uniq_array2 @columns_found;
    if(@columns){
        if(not $view){
            vlogt "validating requested columns against $table_or_view definition";
            foreach my $column (@columns){
                grep { $column eq $_ } @columns_found or die "column '$column' was not found in the Hive $table_or_view definition for '$src'!\n\nDid you specify the wrong column name?\n\nValid columns are:\n\n" . join("\n", @columns_found) . "\n";
            }
        }
    } else {
        vlogt "no columns specified, will index all columns to Elasticsearch";
        vlog3t "auto-determined columns as follows:\n" . join("\n", @columns_found);
        @columns = @columns_found;
    }
    # XXX: ordering of create and select columns must line up precisely for this to work
    $columns = join(",\n    ", @columns);
    foreach my $column (@columns){
        die "Error: no field type found for column '$column'\n" unless $columns{$column};
        $create_columns .= sprintf("%4s%-20s%2s%s,\n", "", $column, "", $columns{$column});
    }
    $create_columns =~ s/,\n$//;
    return $create_columns;
}

sub indexToES($;$){
    my $index     = shift;
    my $partition = shift;
    my $partition_key   = $partition;
    my $partition_value = $partition;
    isESIndex($index) or code_error "invalid Elasticsearch index '$index' passed to indexToES()";
    vlog;
    vlogt "# " . "=" x 76 . " #";
    vlogt "starting processing of $table_or_view $src " . ( $partition ? "partition $partition " : "" ) . "to index '$index'";
    get_columns() unless (@columns_found and $create_columns);
    if($partition){
        # done at option parsing time as well as partition iteration time from Hive show partitions
        #$partition =~ /^([$valid_partition_key_chars]+=[$valid_partition_value_chars]+)$/ or die "ERROR: invalid partition '$partition' detected\n";
        #$partition = $1;
        $partition_key   =~ s/=.*$//;
        $partition_value =~ s/^.*=//;
        isChars($partition_key, $valid_partition_key_chars) or die "ERROR: invalid partition key '$partition_key' detected\n";
        isChars($partition_value, $valid_partition_value_chars) or die "ERROR: invalid partition value '$partition_value' detected\n";
        $index .= "_$partition_value" if $suffix_index and defined($partition_value);
        if(not grep { $partition_key eq $_ } @columns_found){
            die "Partition key '$partition_key' is not defined in the list of columns available in the table '$table'!\n";
        }
    }
    my $indices = $es->indices;
    #if($skip_existing and grep { $index eq $_ } get_ES_indices()){
    if($skip_existing){
        vlogt "user requested to skip existing index, checking if index '$index' exists";
        # XXX: we don't want the whole script to crash if ES isn't available temporarily, but there would be a small race condition here if ignoring errors where this call fails but the Elasticsearch cluster/network then recovers and we re-index data that is already there... may be better to let it fail the script. If we need really want to be more robust maybe a shell loop on this script giving one partition per loop iteration may be better
        #if($es->indices->exists('index' => $index, 'ignore' => $es_ignore_errors)){
        if($es->indices->exists('index' => $index)){
            vlogt "index '$index' already exists and user requested --skip-existing, skipping index '$index'";
            return 1;
        }
    }
    my $job_name = "$src=>ES" . ( $partition ? "-$partition" : "" );
    # Hive CLI is really buggy around comments, see http://stackoverflow.com/questions/15595295/comments-not-working-in-hive-cli
    # had to remove semicolons before comments and put the comments end of line / semicolon only after the last comment in each case to make each comment only end of line :-/
    # In fact inline comments caused so many issues I removed them from the HQL altogether
    # XXX: considered templating this but user editing of SQL template could mess job logic up badly, better to force user to change the code to understand such changes are of major impact, also see implications around race conditions and security tainting further above where I started looking at porting to Template Toolkit
# done on CLI now, removed from HQL because "--SET ... -- comments;"  / "--SET ...; -- comments;" is so buggy in parsing
#SET hive.session.id=$job_name --  this is the one that seems to work for Tez but needs to be set further down on CLI;
#SET tez.queue.name=$queue;
# This would occur too late anyway
#SET tez.job.name=$job_name;
# unused
#SET hive.job.name=$job_name;
#SET hive.query.id=$job_name;
    my $hql = "
ADD JAR $elasticsearch_hadoop_hive_jar;
ADD JAR $commons_httpclient_jar;
SET mapreduce.job.name=Hive=$job_name;
SET mapred.job.name=Hive=$job_name;
SET mapreduce.job.queuename=$queue;
SET mapred.job.queuename=$queue;
" . ( $no_task_retries ? "
SET mapreduce.map.maxattempts=1;
SET mapreduce.reduce.maxattempts=1;
SET mapred.map.max.attempts=1;
SET mapred.reduce.max.attempts=1;
SET tez.am.task.max.failed.attempts=0;
" : "" ) . "
SET mapreduce.map.speculative=FALSE;
SET mapreduce.reduce.speculative=FALSE;
SET mapred.map.tasks.speculative.execution=FALSE;
SET mapred.reduce.tasks.speculative.execution=FALSE;
" . ( $verbose > 2 ? "SET -v;" : "") . "
USE $db;
DROP TABLE IF EXISTS ${table}_elasticsearch;
CREATE EXTERNAL TABLE ${table}_elasticsearch (
$create_columns
) STORED BY 'org.elasticsearch.hadoop.hive.EsStorageHandler'
LOCATION '/tmp/${src}_elasticsearch'
TBLPROPERTIES(
                'es.nodes'    = '$es_nodes',
                'es.port'     = '$es_port',
                'es.resource' = '$index/$type', -- used to be \${index}_{partition_field}/\$type and the storage handler would infer the field correctly but now the index name is dynamically generated in code it's no longer needed
                'es.index.auto.create'   = 'true', -- XXX: setting this to false may require type creation which would require manually mapping all Hive types to Elasticsearch types
                'es.batch.write.refresh' = 'false'
             );
INSERT OVERWRITE TABLE ${table}_elasticsearch SELECT
    $columns
FROM $src";
    # XXX: "where $partition" when partition_value=2015-02-14 results in trawling through all the data (looong) and indexes nothing since nothing matches the predicate, MUST USE $partition_key='$partition_value' QUOTED VALUE
    $hql .= " WHERE $partition_key='$partition_value'" if $partition;
    $hql .= ";";
    # could clean up the temporary table mapping but not sure if this will change final exitcode that we rely on to detect indexing failures
    #$hql .= "\nDROP TABLE IF EXISTS ${table}_elasticsearch;";
    my $response;
    my $result;
    # this may fail to recreate the index, may be better to loop on the script instead of allowing dups
    if($es->indices->exists('index' => $index, 'ignore' => $es_ignore_errors)){
        if($recreate_index){
            vlogt "deleting pre-existing index '$index' for re-creation at user's request";
            #$response = curl_elasticsearch_raw "/$index", "DELETE";
            # ignore deletion of any pre-existing index even for $stop_on_failure;
            #my $es_ignore_errors = $es_ignore_errors_orig if $stop_on_failure;
            $es->indices->delete('index' => $index, 'ignore' => $es_ignore_errors);
            $result = create_index($index);
        }
    } else {
        $result = create_index($index);
    }
    $result or vlogt "WARNING: failed to create index" . ( defined($result) ? ": $result" : "");
    #my $cmd = "$hive -S --hiveconf hive.session.id='$src=>ES-$partition' -e '$hql'");
    # TODO: debug + fix why hive.session.id isn't taking effect, I used to use this all the time in all my other scripts doing this same operation
    # passing job name on CLI since it's too late by the time Hive CLI launches Tez has a session with the ID set
    # --hiveconf hive.query.id='$job_name'
    # switch queue in session causes job name to be reset, so put queue up front on CLI
    my $cmd = "$hive " . ( $verbose > 1 ? "-v " : "" ) . "--hiveconf hive.session.id='$job_name' --hiveconf tez.job.name='$job_name' --hiveconf tez.queue.name='$queue' -e \"$hql\"";
    vlogt "running Hive => Elasticsearch indexing process for $table_or_view $src " . ( $partition ? "partition $partition " : "" ) . "(this may run for a very long time)";
    my $start = time;
    # hive -v instead
    # vlog2t $cmd;
    system($cmd);
    my $exit_code = $?;
    my $secs = time - $start;
    my $msg = "with exit code '$exit_code' for index '$index' with $shards shards in $secs secs";
    if($secs > 59){
        $msg .= " => " . sec2human($secs);
    }
    if($exit_code == 0){
        vlogt "refreshing index";
        #$response = curl_elasticsearch_raw "/$index/_refresh", "POST";
        $es->indices->refresh('index' => $index, 'ignore' => $es_ignore_errors); # not the end of the world you can call a manual refresh later
        if($alias){
            vlogt "aliasing index '$index' to alias '$alias'";
            #$response = curl_elasticsearch_raw "/$index/_alias/$alias", "PUT";
            $es->indices->put_alias('index' => $index, 'name' => $alias, 'ignore' => $es_ignore_errors) # again not critical can alias by hand later
        }
        if($optimize){
            vlogt "optimizing index '$index'";
            #$response = curl_elasticsearch_raw "/$index/_optimize?max_num_segments=1", "POST";
            $es->indices->optimize('index' => $index, 'ignore' => $es_ignore_errors); # can optimize later if this fails
        }
        vlogt "INDEXING SUCCEEDED $msg";
        vlogt "don't forget to add replicas (currently 0) and change the refresh interval (currently -1) if needed";
    } else {
        vlogt "INDEXING FAILED $msg";
        if($delete_on_failure){
            vlogt "deleting index '$index' to clean up";
            #delete_elasticsearch_index($index);
            $es->indices->delete('index' => $index, 'ignore' => $es_ignore_errors); # not exit whole script if this fails, we still want to try other partitions
        }
        exit_if_controlc($exit_code);
        if($stop_on_failure){
            vlogt "Stopping on failure";
            exit $ERRORS{"CRITICAL"};
        } elsif(scalar @partitions_found > 1){
            vlogt "Indexing failure detected... sleeping for 10 mins before trying any remaining partitions in case it's a temporary outage";
            sleep 600;
        }
    }
}

#vlog "checking for dependent libraries ES Hadoop and commons httpclient";
foreach my $path (@jar_search_paths){
    vlog3t "going to check path $path for jars";
}
foreach my $path (@jar_search_paths){
    vlog3t "checking path $path for elastticsearch hadoop/hive jar";
    foreach(glob("$path/*.jar"), glob("$path/elasticsearch-hadoop-*/dist/*.jar")){
        if( -f $_){
            if(basename($_) =~ /^elasticsearch-hadoop(?:-hive)?-\d+(?:\.\d+)*(?:\.Beta\d+)?\.jar$/i){
                $elasticsearch_hadoop_hive_jar = abs_path($_);
                vlog2t "found jar $elasticsearch_hadoop_hive_jar";
                $elasticsearch_hadoop_hive_jar = validate_file($elasticsearch_hadoop_hive_jar, "elasticsearch hadoop hive jar", 0, "no vlog");
            }
        }
    }
    # iterate on all the
    last if $elasticsearch_hadoop_hive_jar;
}
foreach my $path (@jar_search_paths){
    vlog3t "checking path $path for commons httpclient jar";
    foreach(glob("$path/*.jar")){
        if( -f $_){
            if(basename($_) =~ /^commons-httpclient.*\.jar$/){
                $commons_httpclient_jar = abs_path($_);
                vlog2t "found jar $commons_httpclient_jar";
                $commons_httpclient_jar = validate_file($commons_httpclient_jar, "commons httpclient jar", 0, "no vlog");
            }
        }
    }
    last if $commons_httpclient_jar;
}
#my $usual_places = " in the usual places, please place the jar in " . abs_path(dirname(__FILE__));
my $usual_places = ", please place the jar in " . abs_path(dirname(__FILE__));
$elasticsearch_hadoop_hive_jar or die "\ncannot find elasticsearch-hadoop-hive.jar or elasticsearch-hadoop.jar$usual_places\n";
$commons_httpclient_jar        or die "\ncannot find commons-httpclient.jar$usual_places\n";
vlog2t "using jar $elasticsearch_hadoop_hive_jar";
vlog2t "using jar $commons_httpclient_jar";

# Kerberos - this may fail, the Hadoop cluster may not be kerberized, but it's not enough reason to not try, the Hive job can fail later anyway and be reported then, this is more for scripting convenience when looping on this program to make sure the Kerberos ticket gets refreshed
if(which($kinit)){
    my $kinit_cmd = "$kinit -R";
    vlog2t $kinit_cmd;
    my @output = cmd($kinit_cmd, 1);
    vlog2 join("\n", @output);
}

if($table){
    vlogt "getting Hive partitions for table ${tabledb}$table (this may take a minute)";
    # define @partitions_found separately for quick debugging commenting out getting partitions which slows me down
    $partitions_found = `$hive -S $hive_desc_opts --hiveconf hive.session.id=ES-partitions -e 'use $db; show partitions $table' 2>/dev/null`;
    if($? != 0 and $suffix_index){
        vlogt "Failed to determine partitions from table '${tabledb}$table' for --suffix-index. We have nothing to suffix to the index. Did you specify a non-existent table or perhaps --table <view>?\n";
        exit $ERRORS{"UNKNOWN"};
    }
    exit_if_controlc($?);
    @partitions_found = split(/\n/, $partitions_found);
    vlogt "${tabledb}$table is " . ( @partitions_found ? "" : "not ") . "a partitioned table";
}

if(@partitions and not $suffix_index){
    warn "WARNING: you have specified partition(s) but not --suffix-index, are you sure you mean to index all partitions to the same index??\n";
} elsif(@partitions_found and not $suffix_index){
    warn "WARNING: partition(s) have been detected and will be iterated over but you have not specified --suffix-index, are you sure you mean to index all partitions to the same index??\n";
}

if(@partitions){
    foreach my $partition (@partitions){
        if(not grep { "$partition" eq $_ } @partitions_found){
            die "partition '$partition' does not exist in list of available partitions for Hive table ${tabledb}$table\n";
        }
    }
    foreach my $partition (@partitions){
        indexToES($index, $partition);
    }
} else {
    # If this is a partitioned table then index it by partition to allow for easier partial restarts - important when dealing with very high scale
    if(@partitions_found){
        vlogt "partitioned table and no partitions specified, iterating on indexing all partitions";
        my $answer = prompt "Are you sure you want to index all partitions of Hive table '${tabledb}$table' to Elasticsearch? (this could be a *lot* of data to index and may take a very long time) [y/N]";
        vlog;
        isYes($answer) or die "aborting...\n";
        if($recreate_index){
            vlogt "index re-creation requested before indexing (clean index re-build)";
            my $answer = prompt "Are you sure you want to delete and re-create all Elasticsearch indices for all partitions of Hive table '${tabledb}$table'? (this will delete and re-index them one-by-one which could be a *lot* of data to re-index and may take a very long time) [y/N]";
            vlog;
            isYes($answer) or die "aborting...\n";
        }
        foreach my $partition (@partitions_found){
            # untaint partition since we'll be putting it in to code
            if($partition =~ /^([$valid_partition_key_chars]+=[$valid_partition_value_chars]+)$/){
                $partition = $1;
            } else {
                quit "UNKNOWN", "invalid partition '$partition' detected in Hive table when attempting to iterate and index all partitions. Re-run with -vvv and paste in to a ticket at the following URL for a fix/update: https://github.com/harisekhon/devops-perl-tools/issues";
            }
            indexToES($index, $partition);
        }
    } else {
        if($suffix_index){
            die "requested to suffix partition value to index but no partition(s) were specified or found" . ( $table ? "" : " and no table was specified to auto-determine any partitions!" ) . "\n";
        }
        indexToES($index);
    }
}
vlogt "Finished";
