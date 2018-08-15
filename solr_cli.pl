#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-03-06 19:10:38 +0000 (Fri, 06 Mar 2015)
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

use strict;
use warnings;
use Cwd 'abs_path';
# abs_path also resolve the symlink for __FILE__
my $srcdir = abs_path(dirname(abs_path(__FILE__)));
my $env_file = "$srcdir/solr/solr-env.sh";
our $DESCRIPTION = "Solr command line utility to make it easier and shorter to manage Solr / SolrCloud via the Collections & Core APIs - I got bored of using long curl commands all the time and this is better than having a bunch of shell scripts.

Make sure to set your Solr details in either your shell environment or in '$env_file' to avoid typing common parameters all the time. Shell environment takes priority over solr-env.sh (you should 'source $env_file' to add those settings into the shell environment if needed)

Dynamically finds core names if the --core value is not a present core but is found to be a prefix in the form \${core}_shardX_replicaN. This means you can use this same command exactly against all the Solr servers in say a bash for loop without changing the command or needing to know the dynamically generated core names ahead of time.

Tested on Solr / SolrCloud 4.x";

our $DESCRIPTION_CONFIG = "For SolrCloud upload / download config zkcli.sh is must be in the \$PATH and if on Mac must appear in \$PATH before zookeeper/bin otherwise Mac matches zkCli.sh due to Mac case insensitivity. Alternatively specify ZKCLI_PATH explicitly in solr-env.sh";

our $VERSION = "0.5.3";

my $path;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    $path = $ENV{'PATH'};
}
use HariSekhonUtils;
use HariSekhon::Solr;
use HariSekhon::ZooKeeper 'validate_zookeeper_ensemble';
use Data::Dumper;
$Data::Dumper::Terse = 1;

# restore user path and untaint
$path =~ /(.*)/;
$ENV{'PATH'} = $1;

set_timeout_max(1200);
set_timeout_default(300);

my $createalias         = 0;
my $deletealias         = 0;
my $create_collection   = 0;
my $commit_collection   = 0;
my $clusterprop         = 0;
my $soft_commit;
my $download_config     = 0;
my $truncate_collection = 0;
my $delete_collection   = 0;
my $reload_collection   = 0;
my $reload_core         = 0;
my $request_core_recovery = 0;
my $unload_core         = 0;
my $create_shard        = 0;
my $delete_shard        = 0;
my $split_shard         = 0;
my $split_all_shards    = 0;
my $add_replica         = 0;
my $delete_replica      = 0;
my $replica_opts;
my $upload_config       = 0;
my $collection_opts;
my $config_name;
my $zookeeper_ensemble;
my $key;
my $value;

%options = (
    %hostoptions,
);

my %options_collection_opts = (
    "T|create-collection-opts=s" => [ \$collection_opts, "Options for creating a solr collection in the form 'key=value&key2=value2' (\$SOLR_COLLECTION_OPTS)" ],
);
my %options_key_value = (
    "K|key=s"   => [ \$key,     "Property key" ],
    "L|value=s" => [ \$value,   "Property value (deletes the given key if this value is not set)" ],
);
my %options_solrcloud_config = (
    "n|config-name=s"    => [ \$config_name,          "SolrCloud config name, required for --upload-config/--download-config - will also use this for the local directory name (\$SOLRCLOUD_CONFIG)" ],
    "Z|zk|zkhost=s"      => [ \$zookeeper_ensemble,   "ZooKeeper ensemble for uploading / downloading SolrCloud configs (\$SOLR_ZOOKEEPER)" ],
);

my %options_solrcloud_replica_opts = (
    "replica-opts=s" => [ \$replica_opts, "Replica creation options in the form 'key=value&key2=value2'" ],
);

my %options_softcommit = (
    "soft-commit"    => [ \$soft_commit,  "Do a soft commit instead of a hard commit on given collection" ],
);

#sub remove_collection_opts(){
#    foreach(keys %solroptions_collection){
#        delete $options{$_};
#    }
#}
#
#sub remove_core_opts(){
#    foreach(keys %solroptions_core){
#        delete $options{$_};
#        delete $options{"C|core=s"};
#    }
#}

if($progname =~ /collection|shard|replica/){
    %options = (
        %options,
        %solroptions_collection,
        %solroptions_context,
    );
    $soft_commit         = 1  if $progname =~ /softcommit/;
    $delete_collection   = 1  if $progname =~ /delete_collection/;
    $list_collections    = 1  if $progname =~ /list_collections/;
    $reload_collection   = 1  if $progname =~ /reload_collection/;
    $split_all_shards    = 1  if $progname =~ /split_all_shards/;
    if($progname =~ /\bcommit_collection/){
        $commit_collection   = 1;
        %options = ( %options, %options_softcommit );
    } elsif($progname =~ /empty_collection|truncate_collection/){
        $truncate_collection = 1;
        # no soft commit, it doesn't clear docs from the index they still appear in query
        #%options = ( %options, %options_softcommit );
    } elsif ($progname =~ /create_collection/) {
        $create_collection = 1;
        %options = ( %options, %options_collection_opts);
    } elsif ($progname =~ /shard/) {
        $create_shard = 1  if $progname =~ /create_shard/;
        $delete_shard = 1  if $progname =~ /delete_shard/;
        $list_shards  = 1  if $progname =~ /list_shards/;
        $split_shard  = 1  if $progname =~ /split_shard/;
        %options = ( %options, %solroptions_shard);
    } elsif($progname =~ /replica/){
        %options = ( %options, %solroptions_shard, %solroptions_replica);
        $list_replicas  = 1 if $progname =~ /list_replicas/;
        $delete_replica = 1 if $progname =~ /delete_replica/;
        if ($progname =~ /add_replica/) {
            $add_replica = 1;
            %options = ( %options, %solroptions_node, %options_solrcloud_replica_opts);
        }
    }
    # remove other list options to avoid user induced list command clashes and also options at same level which wouldn't make any sense
    if($progname =~ /list/){
        my $type;
        if($progname =~ /list_(\w+)s/){
            $type = $1;
        }
        foreach (keys %options){
            /list/ && delete $options{$_};
            /$type\=/o && delete $options{$_};
        }
    }
} elsif ($progname =~ /alias/) {
    $createalias = 1 if $progname =~ /create/;
    $deletealias = 1 if $progname =~ /delete/;
    %options = ( %options, %solroptions_collection_aliases, %solroptions_collections);
} elsif ($progname =~ /clusterprop/) {
    $clusterprop = 1;
    %options = ( %options, %options_key_value);
} elsif ($progname =~ /config/) {
    $DESCRIPTION =~ s/Tested/$DESCRIPTION_CONFIG

Tested/;
    if ($progname =~ /download_.*config/) {
        $download_config = 1;
    } elsif ($progname =~ /upload_.*config/) {
        $upload_config = 1;
    }
    %options = ( %options, %options_solrcloud_config);
} elsif ($progname =~ /core/) {
    %options = ( %options, %solroptions_core);
    $list_cores = 1  if $progname =~ /list_cores/;
    $reload_core = 1 if $progname =~ /reload_core/;
    $request_core_recovery = 1 if $progname =~ /request_core_recovery/;
    $unload_core = 1 if $progname =~ /unload_core/;
} elsif ($progname =~ /list_nodes/){
    $list_nodes++ if $progname =~ /list_nodes/;
} else {
    $DESCRIPTION =~ s/Make sure/Best not to be called directly but instead via shorter symlinks found under the '$srcdir\/solr\/' directory that are easy to tab complete and only expose a subset of the relevant options, otherwise as you can see below there are a lot of options

Make sure/;
    $DESCRIPTION =~ s/Tested/$DESCRIPTION_CONFIG

Tested/;

    %options = (
        %options,
        %solroptions_collection,
        %solroptions_collections,
        %solroptions_collection_aliases,
        %solroptions_core,
        %solroptions_shard,
        %solroptions_replica,
        %solroptions_node,
        %solroptions_context,
        %ssloptions,
        "create-collection"         => [ \$create_collection,           "Create collection" ],
        "commit-collection"         => [ \$commit_collection,           "Commit collection" ],
        %options_softcommit,
        "truncate-collection"       => [ \$truncate_collection,         "Truncate collection" ],
        "delete-collection"         => [ \$delete_collection,           "Delete collection" ],
        "reload-collection"         => [ \$reload_collection,           "Reload collection" ],
        "reload-core"               => [ \$reload_core,                 "Reload core" ],
        "request-core-recovery"     => [ \$request_core_recovery,       "Request core recovery (not currently documented in CoreAdmin API but I needed this to recover cores which weren't auto-recovering and were stuck behind other cores doing fullCopy :-/ )" ],
        "unload-core"               => [ \$unload_core,                 "Unload core" ],
        "create-shard"              => [ \$create_shard,                "Create named shard, requires --collection" ],
        "delete-shard"              => [ \$delete_shard,                "Delete named shard, requires --collection" ],
        "split-shard"               => [ \$split_shard,                 "Split named shard, requires --collection" ],
        "split-all-shards"          => [ \$split_all_shards,            "Split all shards for given collection" ],
        "add-replica"               => [ \$add_replica,                 "Add replica, requires --collection and --shard" ],
        "delete-replica"            => [ \$delete_replica,              "Delete replica, requires --collection and --shard" ],
        "download-config"           => [ \$download_config,             "Download config from ZooKeeper" ],
        "upload-config"             => [ \$upload_config,               "Upload config to ZooKeeper" ],
        "clusterprop"               => [ \$clusterprop,                 "Set cluster wide property using --key and --value switches" ],
        "create-alias"              => [ \$createalias,                 "Create collection alias" ],
        "delete-alias"              => [ \$deletealias,                 "Delete collection alias" ],
        %options_collection_opts,
        %options_key_value,
        %options_solrcloud_replica_opts,
        %options_solrcloud_config,
    );
}
if($options{"C|core=s"}){
    # change core short key to not clash with C|collection
    $options{"O|core=s"} = $options{"C|core=s"};
    delete $options{"C|core=s"};
}
splice @usage_order, 6, 0, qw/collection core create-collection create-collection-opts commit-collection soft-commit truncate-collection delete-collection reload-collection collection-alias create-alias delete-alias collections reload-core request-core-recovery unload-core shard create-shard delete-shard split-shard split-all-shards add-replica delete-replica node replica replica-opts download-config upload-config config-name zookeeper zk zkhost cluster-property key value list-collections list-collection-aliases list-shards list-replicas list-cores list-nodes http-context/;

get_options();

$commit_collection = 1 if $soft_commit;

my $list_count = $list_collections + $list_collection_aliases + $list_shards + $list_replicas + $list_cores + $list_nodes;
$list_count > 1 and usage "can only list one thing at a time";
unless($list_count){
    my $action_count =
       $create_collection
     + $commit_collection
     + $download_config
     + $truncate_collection
     + $delete_collection
     + $reload_collection
     + $createalias
     + $deletealias
     + $clusterprop
     + $reload_core
     + $request_core_recovery
     + $unload_core
     + $create_shard
     + $delete_shard
     + $split_shard
     + $split_all_shards
     + $add_replica
     + $delete_replica
     + $upload_config;
    if($action_count > 1){
        usage "cannot specify more than one action at a time";
    }
    unless($action_count== 1){
        usage "no action specified";
    }
}

if(-f $env_file ){
    my $fh = open_file $env_file;
    my ($key, $value);
    while(<$fh>){
        s/#.*//;
        /^\s*$/ and next;
        s/\s*export\s+//;
        if(/(\w+)\s*=\s*"?(.*?)"?\s*$/){
            $key   = $1;
            $value = $2;
            grep { $_ eq $key } qw/SOLR_HOST SOLR_PORT SOLR_USER SOLR_PASSWORD SOLR_COLLECTION SOLR_COLLECTION_OPTS SOLR_REPLICA_OPTS SOLR_CORE SOLR_HTTP_CONTEXT SOLR_ZOOKEEPER SOLRCLOUD_CONFIG/ or next;
            unless(defined($ENV{$key})){
                vlog2 "loading from env file =>  $key = $value";
                $ENV{$key} = $value;
            }
        }
    }
    vlog2;
} else {
    warn "'$env_file' not found, not loading convenience environment variables\n";
}

env_creds("Solr");
env_vars("SOLR_COLLECTION",          \$collection);
env_vars("SOLR_COLLECTION_ALIAS",    \$collection_alias);
env_vars("SOLR_COLLECTIONS",         \$collections);
env_vars("SOLR_COLLECTION_OPTS",     \$collection_opts);
env_vars("SOLR_REPLICA_OPTS",        \$replica_opts);
env_vars("SOLR_CORE",                \$core);
env_vars("SOLR_HTTP_CONTEXT",        \$http_context);
env_vars("SOLR_ZOOKEEPER",           \$zookeeper_ensemble);
env_vars("SOLRCLOUD_CONFIG",         \$config_name);

my $zkcli="zkcli.sh";

if($upload_config or $download_config){
    if(defined($ENV{'ZKCLI_PATH'})){
        $zkcli = $ENV{'ZKCLI_PATH'};
        $zkcli =~ /\bzkcli.sh$/ or usage "invalid zkcli.sh path, does not end in zkcli.sh";
        $zkcli = validate_file($zkcli, "zkcli");
    }
    $config_name = validate_dirname($config_name, "config");
    $zookeeper_ensemble = validate_zookeeper_ensemble($zookeeper_ensemble);
} else {
    $host         = validate_host($host);
    $port         = validate_port($port);
    $http_context = validate_solr_context($http_context);
    validate_ssl();
    if($collection_opts){
        $collection_opts =~ /^((?:\w+=[\w\/-]+)(?:\&\w+=[\w\/-]+)*)?$/ or usage "invalid collection opts";
        $collection_opts = $1;
        vlog_option "collection opts", $collection_opts;
    }
    $collection       = validate_solr_collection($collection) if $collection;
    $collection_alias = validate_solr_collection_alias($collection_alias) if $collection_alias;
    $collections      = validate_solr_collections($collections) if $collections;
    $core             = validate_solr_core($core) if $core;
    $shard            = validate_solr_shard($shard) if $shard;
}
if($clusterprop){
    $key = validate_alnum($key,   "key");
    if(defined($value) and $value ne ""){
        $value = validate_alnum($value, "value");
    } else {
        $value = "";
        vlog_option "value", "<unset>";
    }
}

vlog2;
set_timeout();

unless($upload_config or $download_config){
    list_solr_collections();
    list_solr_collection_aliases();
    list_solr_cores();
    list_solr_shards($collection);
    list_solr_replicas($collection, $shard);
    list_solr_nodes();
}

sub curl_solr2($){
    my $url = shift;
    #$url .= "&indent=true";
    $json = curl_solr $url;
    print Dumper($json);
}

sub collection_defined(){
    defined($collection) or usage "collection not defined";
}

sub shard_defined(){
    defined($shard) or usage "shard not defined";
}

sub solrcloud_defined(){
    defined($config_name)   or usage "solrcloud config name not defined";
    defined($zookeeper_ensemble) or usage "zookeeper ensemble not defined";
    my @zoos = split(/\s*,\s*/, $zookeeper_ensemble);
    plural scalar @zoos;
}

sub core_defined(){
    defined($core) or usage "core not defined";
}

sub alias_defined(){
    defined($collection_alias) or usage "collection alias not defined";
}

sub create_alias(){
    alias_defined();
    defined($collections) or usage "collections not defined";
    print "creating collection alias '$collection_alias' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=CREATEALIAS&name=$collection_alias&collections=$collections";
}

sub delete_alias(){
    alias_defined();
    print "deleting collection alias '$collection_alias' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=DELETEALIAS&name=$collection_alias";
}

sub create_collection(){
    collection_defined();
    print "creating collection '$collection' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=CREATE&name=$collection" . ( $collection_opts ? "&$collection_opts" : "" );
}

sub delete_collection(){
    collection_defined();
    print "deleting collection '$collection' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=DELETE&name=$collection";
}

sub commit_collection(;$){
    my $soft = shift;
    collection_defined();
    print(( $soft ? "soft " : "" ) . "committing collection '$collection' via '$host:$port'\n");
    my $commit = ( $soft ? "softCommit" : "commit" );
    curl_solr2 "$http_context/$collection/update/json?$commit=true";
                                       # /update?stream.body=%3Commit/%3E
}

sub reload_collection($){
    my $collection = shift;
    print "reloading collection '$collection' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=RELOAD&name=$collection";
}

sub clusterprop($$){
    my $key   = shift;
    my $value = shift;
    print "setting Solr cluster property '$key'='$value' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=CLUSTERPROP&name=$key&val=$value";
}

sub reload_core(){
    core_defined();
    $core = find_solr_core($core) || die "failed to find solr core name '$core'\n";
    print "reloading core '$core' at '$host:$port'\n";
    curl_solr2 "$solr_admin/cores?action=RELOAD&core=$core";
}

sub request_core_recovery(){
    core_defined();
    $core = find_solr_core($core) || die "failed to find solr core name '$core'\n";
    print "requesting recovery for core '$core' at '$host:$port'\n";
    curl_solr2 "$solr_admin/cores?action=REQUESTRECOVERY&core=$core";
}

sub unload_core(){
    core_defined();
    $core = find_solr_core($core) || die "failed to find solr core name '$core'\n";
    print "unloading core '$core' at '$host:$port'\n";
    curl_solr2 "$solr_admin/cores?action=UNLOAD&core=$core";
}

sub truncate_collection(){
    collection_defined();
    print "truncating collection '$collection' via '$host:$port'\n";
    $ua->default_header("Content-type", "application/json");
    $json = curl_solr "$http_context/$collection/update/json", "POST", '{"delete": { "query":"*:*", "commitWithin":500 } }';
                                              # /update?stream.body=%3Cdelete%3E%3Cquery%3E*:*%3C/query%3E%3C/delete%3E
    print Dumper($json);
    # no soft commit, it doesn't clear docs from the index they still appear in query
    commit_collection();
}

sub create_shard(){
    collection_defined();
    shard_defined();
    print "creating shard '$shard' in collection '$collection' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=CREATESHARD&collection=$collection&shard=$shard";
}

sub delete_shard(){
    collection_defined();
    shard_defined();
    print "deleting shard '$shard' in collection '$collection' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=DELETESHARD&collection=$collection&shard=$shard";
}

sub split_shard($){
    my $shard = shift;
    collection_defined();
    print "splitting shard '$shard' for collection '$collection' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=SPLITSHARD&collection=$collection&shard=$shard";
}

sub split_all_shards(){
    collection_defined();
    print "splitting all shards in collection '$collection' via '$host:$port'\n";
    my @shards = get_solr_shards($collection);
    foreach my $shard (@shards){
        split_shard($shard);
    }
}

sub add_replica(){
    defined($solr_node) or usage "node not defined";
    shard_defined();
    # not bothering to do much node checking since the permitting format isn't clear, Solr server can handle and throw the exception
    print "adding replica to node '$solr_node' for collection '$collection' shard '$shard' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=ADDREPLICA&collection=$collection&shard=$shard&node=$solr_node" . ( $replica_opts ? "&$replica_opts" : "" );
}

sub delete_replica(){
    defined($replica) or usage "replica not defined";
    shard_defined();
    print "deleting replica '$replica' from collection '$collection' shard '$shard' via '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=DELETEREPLICA&collection=$collection&shard=$shard&replica=$replica";
}

sub download_config(){
    solrcloud_defined();
    print "downloading SolrCloud ZooKeeper config '$config_name' from ZooKeeper$plural '$zookeeper_ensemble'\n";
    my @output = cmd("$zkcli -zkhost '$zookeeper_ensemble' -cmd downconfig -confdir '$config_name' -confname '$config_name'", 1);
    print join("\n", @output) . "\n";
}

sub upload_config(){
    solrcloud_defined();
    print "uploading SolrCloud ZooKeeper config '$config_name' to ZooKeeper$plural '$zookeeper_ensemble'\n";
    my @output = cmd("$zkcli -zkhost '$zookeeper_ensemble' -cmd upconfig -confdir '$config_name' -confname '$config_name'", 1);
    print join("\n", @output) . "\n";
    my @collections = get_solr_collections();
    if(grep { $_ eq $config_name } @collections){
        reload_collection($config_name);
    }
}

create_collection()     if $create_collection;
clusterprop($key, $value) if $clusterprop;
commit_collection($soft_commit) if $commit_collection;
download_config()       if $download_config;
truncate_collection()   if $truncate_collection;
delete_collection()     if $delete_collection;
reload_collection($collection) if $reload_collection;
create_alias()          if $createalias;
delete_alias()          if $deletealias;
reload_core()           if $reload_core;
request_core_recovery() if $request_core_recovery;
unload_core()           if $unload_core;
create_shard()          if $create_shard;
delete_shard()          if $delete_shard;
split_shard($shard)     if $split_shard;
split_all_shards()      if $split_all_shards;
add_replica()           if $add_replica;
delete_replica()        if $delete_replica;
upload_config()         if $upload_config;
