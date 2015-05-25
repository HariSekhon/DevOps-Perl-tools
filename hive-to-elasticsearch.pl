#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-05-23 09:19:57 +0100 (Sat, 23 May 2015)
#
#  https://github.com/harisekhon
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Tool to automate indexing from an arbitrary Hive table to an Elasticsearch index, with support for Kerberos and large scale partitioned tables.

This is a completely new rewrite to unify a bunch of other scripts I was using for a selection of Hive tables in a more generically reusable way.

You should supply the full list of Elasticsearch nodes for --nodes, otherwise defaults to localhost:9200.

Kerberos is supported but you must generate a TGT before running this program and the ticket must be renewable. This helps when looping through Hive table partitions as it will refresh the TGT to stop it expiring before each partition, which is especially important for high scale partitioned table indexing which can take days for billions of records if iterating on lots of partitions.

The programs 'hive' and 'kinit' are assummed to be in the base PATH $ENV{PATH}, otherwise you must set them at the top of this program.

Creates hive table of same name as each indexed table with '_elasticsearch' suffixed to it. Deletes and re-creates that _elasticsearch table each time to ensure correct data is sent and aligned with Elasiticsearch.

Libraries Required:

ES Hadoop - https://www.elastic.co/downloads/hadoop

You need the 'elasticsearch-hadoop-hive.jar' from the link above as well as the Apache 'commons-httpclient.jar' (which should be supplied inside your Hadoop distribution) in to the same directory as this program. For conveneience this program will attempt to automatically find the commons-httpclient.jar on Hortonworks HDP in the standard distribution paths and the elasticsearch-hadoop-hive.jar / elasticsearch-hadoop.jar if you just unpack the zip from Elasticsearch directly in to the same directory as this program. If you put those two required jars directly adjacent to this program that will also work.

Tested on Hortonworks HDP 2.2 using Hive 0.14 => Elasticsearch 1.2.1, 1.4.1, 1.5.2 using ES Hadoop 2.1.0";

$VERSION = "0.6";

# TODO: make sure all references are switched from personal nagios library to using the official elasticsearch client for node failover robustness

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Elasticsearch;
use Cwd 'abs_path';
use Search::Elasticsearch;

########################
#
# Your settings go here
#
# You can hard code your JAR paths here if needed
my $elasticsearch_hadoop_hive_jar = "";
my $commons_httpclient_jar        = "";

# Hardcode the paths to your hive and kinit commands if they're not in the basic $PATH (which gets scrubbed from the environment for security taint mode) to just the system paths
my $hive  = 'hive';
my $kinit = 'kinit';

# search these locations for elasticsearch and http commons jars
my @jar_search_paths = qw{ . /usr/hdp/current/hadoop-client/lib /opt/cloudera/parcels/CDH/lib };

########################

# bulk indexing billions of documents can take hours
set_timeout_max(86400 * 7);
set_timeout_default(86400 * 3);

$verbose = 1;

my $db = "default";
my $table;
my $columns;
my $alias;
my $shards_default = 5;
my $shards = $shards_default;
my $delete_before;
my $delete_on_failure;
my $no_task_retries;
my $optimize;
my $partition_key;
my $partition_values;
my $skip_existing;
my $queue = "default";

%options = (
    %nodeoptions,
    "d|db|database=s"       =>  [ \$db,                 "Hive database (defaults to the 'default' database" ],
    "T|table=s"             =>  [ \$table,              "Hive table to index to Elasticsearch" ],
    "C|columns=s"           =>  [ \$columns,            "Hive table columns in the given table to index to Elasticsearch, comma separated (defaults to indexing all columns)" ],
    "p|partition-key=s"     =>  [ \$partition_key,      "Hive table partition. Optional but recommended for high scale and to split Elasticsearch indexing jobs in to more easily repeatable units in case of failures" ],
    "u|partition-values=s"  => [ \$partition_values,    "Hive table partition value(s), can be comma separated to index multiple partitions. If multiple partitions are specified separated by commas then the index name will be suffixed with the partition value. Optional, but requires --parition-key if specified" ],
    %elasticsearch_index,
    %elasticsearch_type,
    "s|shards=s"            => [ \$shards,              "Number of shards to create new index as, must be a positive integer (default: $shards_default)" ],
    "q|queue=s"             => [ \$queue,               "Hadoop scheduler queue to run the Hive job in (use this to throttle and not overload Elasticsearch and trigger indexing job failures, default: $queue)" ],
    "delete-before-index"   => [ \$delete_before,       "Delete Elasticsearch index if already existing to truncate and ensure it has the correct settings (eg. number of --shards). Use when using autogenerated keys to avoid duplicates" ],
    "delete-on-failure"     => [ \$delete_on_failure,   "Delete Elasticsearch index if the indexing job fails, useful when combined with --skip-existing to be able to re-run safely over and over to fill in new or missing partitions that haven't been indexed yet" ],
    "skip-existing"         => [ \$skip_existing,       "Skip job if the Elasticsearch index already exists (useful with --delete-on-failure to give safe retry semantics for indexing only missing Hive partitions that did not successfully complete on previous runs)" ],
    "no-task-retries"       => [ \$no_task_retries,     "Fails job if any task fails to prevent duplicates being introduced if using autogenerated IDs as it be may be better to combine with --delete-before-index or --delete-on-failure to recreate index without duplicates in that case" ],
    "a|alias=s"             => [ \$alias,               "Elasticsearch alias to add the index to after it's finished indexing (optional)" ],
    "o|optimize"            => [ \$optimize,            "Optimize Elasticsearch index after indexing and aliasing finishes" ],
);
#@usage_order .= # TODO ;
@usage_order = qw/node nodes port db database table columns partition-key partition-values index type shards queue delete-before-index delete-on-failure skip-existing no-task-retries alias optimize/;

get_options();

my @nodes = validate_nodeport_list($nodes);
$host     = $nodes[0];
$port     = validate_port($port);
$db       = validate_database($db, "Hive");
$table    = validate_database_tablename($table, "Hive");
my @columns;
if($columns){
    foreach(split(/\s*,\s*/, $columns)){
        $_ = validate_database_columnname($_);
        push(@columns, $_);
        system("echo column = $_");
    }
}
$index  = validate_elasticsearch_index($index);
$type or $type = $index;
$type   = validate_elasticsearch_type($type);
$alias  = validate_elasticsearch_alias($alias) if defined($alias);
$shards = validate_int($shards, "shards", 1, 1000);
$queue  = validate_alnum($queue, "queue");
if((defined($partition_key) and not defined($partition_values)) or (defined($partition_values) and not defined($partition_key))){
    usage "if using partitions must specify both --partition-key and --partition-value";
}
#$partition_key = validate_alnum($partition_key, "partition key") if $partition_key;
$partition_key = validate_chars($partition_key, "partition key", "A-Za-z0-9_-") if $partition_key;
my @partitions;
#$partition_value = validate_chars($partition_value, "partition value", "A-Za-z0-9_-");
if($partition_values){
    foreach(split(/\s*,\s*/, $partition_values)){
        $_ = validate_chars($_, "partition value", "A-Za-z0-9_-");
        push(@partitions, "$partition_key=$_");
    }
}
($skip_existing and $delete_before) and usage "--skip-existing and --delete-before-index are mutually exclusive!";

my $es_nodes = join(",", @nodes);
my $es_port  = $port;

my $node_num = scalar @nodes;
foreach(my $i=0; $i < $node_num; $i++){
    $nodes[$i] =~ /:/ or $nodes[$i] .= ":$port";
}

vlog2;
set_timeout();

my $es = Search::Elasticsearch->new(
    'nodes'    => @nodes,
    #'cxn_pool' => 'Sniff',
    #'trace_to' => 'Stderr'
);

sub create_index($){
    my $index = shift;
    vlogt "creating index '$index' with $shards shards, no replicas and no refresh in order to maximize bulk indexing performance";
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
        'index' => $index,
        'body'  => "{
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

my $num_partitions = scalar @partitions;

sub indexToES($;$){
    my $index     = shift;
    my $partition = shift;
    $index .= $partition if $num_partitions > 1;
    isESIndex($index) or code_error "invalid Elasticsearch index '$index' passed to indexToES()";
    vlogt "starting processing of table $db.$table " . ( $partition ? "partition $partition " : "" ). "to index '$index'";
    my $indices = $es->indices;
    #if($skip_existing and grep { $index eq $_ } get_ES_indices()){
    if($skip_existing){
        vlogt "user requested to skip existing index, checking if index '$index' exists";
        if($es->indices->exists('index' => $index)){
            vlogt "index '$index' already exists and user requested --skip-existing, skipping index '$index'";
            return 1;
        }
    }
    vlogt "checking columns in table $db.$table (this may take a minute)";
    # or try hive -S -e 'SET hive.cli.print.header=true; SELECT * FROM $db.$table LIMIT 0'
    my $output = `hive -S -e 'describe $db.$table' 2>/dev/null`;
    my @output = split(/\n/, $output);
    my %columns;
    my @columns2;
    foreach(@output){
        # bit hackish but quick to do, take lines which look like "^column_name<space>column_type$" - doesn't support
        if(/^\s*([^\s]+)\s+([A-Za-z]+)\s*$/){
            $columns{$1} = $2;
            push(@columns2, $1);
        }
    }
    if(@columns){
        vlogt "validating requested columns against table definition";
        foreach my $column (@columns){
            grep { $column eq $_ } @columns2 or die "column '$column' was not found in the Hive table definition for '$db.$table'!\n\nDid you specify the wrong column name?\n\nValid columns are:\n\n" . join("\n", @columns2) . "\n";
        }
    } else {
        vlogt "no columns specified, will index all columns to Elasticsearch";
        vlogt "auto-determined columns to be: @columns2";
        @columns = @columns2;
    }
    my $columns = join(",\n    ", @columns);
    my $create_columns = "";
    foreach my $column (@columns){
        $create_columns .= "    $column    $columns{$column},\n";
    }
    $create_columns =~ s/,\n$//;
    my $job_name = "$db.$table=>ES" . ( $partition ? "-$partition" : "" );
    # Hive CLI is really buggy around comments, see http://stackoverflow.com/questions/15595295/comments-not-working-in-hive-cli
    # had to remove semicolons before comments and put the comments end of line / semicolon only after the last comment in each case to make each comment only end of line :-/
    # XXX: considered templating this but user editing of SQL template could mess job logic up badly, better to force user to change the code to understand such changes are of major impact
    my $hql = "
ADD JAR $elasticsearch_hadoop_hive_jar;
ADD JAR $commons_httpclient_jar;
SET hive.session.id='$job_name';
SET tez.queue.name=$queue;
SET mapreduce.job.queuename=$queue;
SET mapreduce.map.maxattempts=1;
SET mapreduce.reduce.maxattempts=1;
SET mapred.map.max.attempts=1;
SET mapred.reduce.max.attempts=1;
SET tez.am.task.max.failed.attempts=0;
SET mapreduce.map.speculative=FALSE;
SET mapreduce.reduce.speculative=FALSE;
SET mapred.map.tasks.speculative.execution=FALSE;
SET mapred.reduce.tasks.speculative.execution=FALSE;
SET -v;
USE $db;
DROP TABLE IF EXISTS ${table}_elasticsearch;
CREATE EXTERNAL TABLE ${table}_elasticsearch (
$create_columns
) STORED BY 'org.elasticsearch.hadoop.hive.EsStorageHandler'
LOCATION '/tmp/${table}_elasticsearch'
TBLPROPERTIES(
                'es.nodes'    = '$es_nodes',
                'es.port'     = '$es_port',
                'es.resource' = '$index/$type',
                'es.index.auto.create'   = 'true', -- XXX: setting this to false may require type creation which would require manually mapping all Hive types to Elasticsearch types
                'es.batch.write.refresh' = 'false'
             );
INSERT INTO TABLE ${table}_elasticsearch SELECT
    $columns
FROM $table";
    $hql .= " WHERE $partition" if $partition;
    $hql .= ";";
    my $response;
    my $result;
    if($es->indices->exists('index' => $index)){
        if($delete_before){
            vlogt "deleting pre-existing index '$index' at user's request";
            #$response = curl_elasticsearch_raw "/$index", "DELETE";
            $es->indices->delete('index' => $index, 'ignore' => 404);
        }
        $result = create_index($index);
    } else {
        $result = create_index($index);
    }
    $result or vlogt "WARNING: failed to create index: $result";
    #my $cmd = "hive -S --hiveconf hive.session.id='$db.$table=>ES-$partition' -e '$hql'");
    my $cmd = "hive -v --hiveconf hive.session.id='$job_name' -e \"$hql\"";
    vlogt "running Hive => Elasticsearch indexing process for table $db.$table " . ( $partition ? "partition $partition " : "" ) . "(this may run for a very long time)";
    my $start = time;
    # hive -v instead
    # vlog2t $cmd;
    system($cmd);
    my $exit_code = $?;
    my $secs = time - $start;
    my $msg = "for index '$index' with $shards shards in " . sec2human($secs);
    if($secs > 60){
        $msg .= " ($secs)";
    }
    if($exit_code == 0){
        vlogt "refreshing index";
        #$response = curl_elasticsearch_raw "/$index/_refresh", "POST";
        $es->indices->refresh('index' => $index);
        if($alias){
            vlogt "aliasing index '$index' to alias '$alias'";
            #$response = curl_elasticsearch_raw "/$index/_alias/$alias", "PUT";
            $es->indices->put_alias('index' => $index, 'name' => $alias)
        }
        if($optimize){
            vlogt "optimized index '$index'";
            #$response = curl_elasticsearch_raw "/$index/_optimize?max_num_segments=1", "POST";
            $es->indices->optimize('index' => $index);
        }
        vlogt "INDEXING SUCCEEDED $msg";
        vlogt "don't forget to add replicas (currently 0) and change the refresh interval (currently -1) if needed";
    } else {
        vlogt "INDEXING FAILED $msg";
        if($delete_on_failure){
            vlogt "deleting index '$index' to clean up";
            #delete_elasticsearch_index($index);
            $es->indices->delete('index' => $index, 'ignore' => 404);
        }
    }
}

$status = "OK";

vlog "# " . "=" x 76 . " #";
vlog "#  Hive database '$db' table '$table' => Elasticsearch";
#plural @nodes;
#vlog2 "(node$plural: '$es_nodes')";
vlog "# " . "=" x 76 . " #\n";

vlogt "Starting indexing run";
#vlog "checking for dependent libraries ES Hadoop and commons httpclient";
foreach my $path (@jar_search_paths){
    foreach(glob("$path/*.jar"), glob("$path/elasticsearch-hadoop-*/dist/*.jar")){
        if( -f $_){
            if(basename($_) =~ /^elasticsearch-hadoop(?:-hive)?-\d+(?:\.\d+)*(?:\.Beta\d+)?\.jar$/i){
                $elasticsearch_hadoop_hive_jar = abs_path($_);
                vlog2t "found $elasticsearch_hadoop_hive_jar";
                $elasticsearch_hadoop_hive_jar = validate_file($elasticsearch_hadoop_hive_jar, 0, "elasticsearch hadoop hive jar", "no vlog");
                last;
            }
        }
    }
}
foreach my $path (@jar_search_paths){
    foreach(glob("$path/*.jar")){
        if( -f $_){
            if(basename($_) =~ /^commons-httpclient.*\.jar$/){
                $commons_httpclient_jar = abs_path($_);
                vlog2t "found $commons_httpclient_jar";
                $commons_httpclient_jar = validate_file($commons_httpclient_jar, 0, "commons httpclient jar", "no vlog");
                last;
            }
        }
    }
}
#my $usual_places = " in the usual places, please place the jar in " . abs_path(dirname(__FILE__));
my $usual_places = ", please place the jar in " . abs_path(dirname(__FILE__));
$elasticsearch_hadoop_hive_jar or die "\ncannot find elasticsearch-hadoop-hive.jar or elasticsearch-hadoop.jar$usual_places\n";
$commons_httpclient_jar        or die "\ncannot find commons-httpclient.jar$usual_places\n";

# Kerberos - this may fail, the Hadoop cluster may not be kerberized, but it's not enough reason to not try, the Hive job can fail later anyway and be reported then, this is more for scripting convenience when looping on this program to make sure the Kerberos ticket gets refreshed
if(which($kinit)){
    my $kinit_cmd = "$kinit -R";
    vlog2t $kinit_cmd;
    my @output = cmd($kinit_cmd, 1);
    vlog2 join("\n", @output);
}

my ($partitions_found, @partitions_found);
vlogt "getting Hive partitions for table $db.$table (this may take a minute)";
# define @partitions_found separately for quick debugging commenting out getting partitions which slows me down
$partitions_found = `$hive -S -e 'show partitions $db.$table' 2>/dev/null`;
@partitions_found = split(/\n/, $partitions_found);
vlogt "$db.$table is " . ( @partitions_found ? "" : "not ") . "a partitioned table";

if($delete_before){
    vlogt "deletion of index requested before indexing (clean index re-build)";
    if(@partitions_found and not @partitions){
        # XXX: TODO: yes | ./script doesn't work - find out why
        vlog;
        my $answer = prompt "Are you sure you want to delete and re-create the entire Elasticsearch index for the Hive table '$db.$table'? [y/N]";
        vlog;
        isYes($answer) or die "aborting...\n";
    }
    #vlogt "checking if index '$index' already exists...";
    #if(ESIndexExists($index)){
        #vlogt "index '$index' already exists";
        #if(@partitions){
        #} else {
                #my $answer = prompt "\nAre you sure you want to delete and re-create the Elasticsearch index from the Hive table '$db.$table'? [y/N]";
                #if(isYes($answer)){
                    #vlogt "deleting Elasticsearch index '$index' before starting indexing run";
                    #$es->indices->delete('index' => $index, 'ignore' => 404);
                #}
        #    } else {
        #        vlogt "index '$index' doesn't exist yet";
        #    }
        #}
    #}
    #vlog;
}

if(@partitions){
    foreach my $partition (@partitions){
        if(not grep { "$partition" eq $_ } @partitions_found){
            die "partition '$partition' does not exist in list of available partitions for Hive table $db.$table\n";
        }
    }
    foreach my $partition (@partitions){
        indexToES($index, $partition);
    }
} else {
    # If this is a partitioned table then index it by partition to allow for easier partial restarts - important when dealing with very high scale
    if(@partitions_found){
        foreach my $partition (@partitions_found){
            # untaint partition since we'll be putting it in to code
            if($partition =~ /^([A-Za-z0-9_-]+=[A-Za-z0-9_-])$/){
                $partition = $1;
            } else {
                quit "UNKNOWN", "invalid partition '$partition' detected in Hive table when attempting to iterate and index all partitions. Re-run with -vvv and paste in to a ticket at the following URL for a fix/update: https://github.com/harisekhon/toolbox/issues";
            }
            indexToES($index, $partition);
        }
    } else {
        indexToES($index);
    }
}
vlogt "Finished";
