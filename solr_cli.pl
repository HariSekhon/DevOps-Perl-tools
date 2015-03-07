#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2015-03-06 19:10:38 +0000 (Fri, 06 Mar 2015)
#
#  https://github.com/harisekhon
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

our $DESCRIPTION = "Solr command line utility to make it easier and shorter to manage Solr often - I got bored of using long curl commands all the time!

Make sure to set your Solr details in either your shell environment or in adjacent solr-env.sh or solr/solr-env.sh to avoid typing common parameters all the time. Shell environment takes priority over solr-env.sh (you should 'source solr/solr-env.sh' to add those settings into the shell environment if needed)

For SolrCloud upload / download config zkcli.sh is must be in the \$PATH and if on Mac must appear in \$PATH before zookeeper/bin otherwise Mac matches zkCli.sh due to Mac case insensitivity (or alternatively specify ZKCLI_PATH in solr-env.sh

Tested on Solr / SolrCloud 4.x";

$VERSION = "0.1";

use strict;
use warnings;
my $path;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    $path = $ENV{'PATH'};
}
use HariSekhonUtils;
use HariSekhon::Solr;
use HariSekhon::ZooKeeper 'validate_zookeeper_ensemble';
use Cwd 'abs_path';
use Data::Dumper;
$Data::Dumper::Terse = 1;

# restore user path and untaint
$path =~ /(.*)/;
$ENV{'PATH'} = $1;

set_timeout_max(600);
set_timeout_default(60);

my $create_collection   = 0;
my $commit_collection   = 0;
my $download_config     = 0;
my $truncate_collection = 0;
my $delete_collection   = 0;
my $reload_collection   = 0;
my $reload_core         = 0;
my $split_shard;
my $split_shards        = 0;
my $split_all_shards    = 0;
my $upload_config       = 0;
my $collection_opts;
my $config_name;
my $zookeeper_ensemble;

%options = (
    %hostoptions,
);

my %options_collection_opts = (
        "T|create-collection-opts=s" => [ \$collection_opts, "Options for creating a solr collection in the form 'key=value&key2=value2' (\$SOLR_COLLECTION_OPTS)" ],
);
my %options_solrcloud_config = (
        "N|config-name=s"    => [ \$config_name,          "SolrCloud config name, required for --upload-config/--download-config - will also use this for the local directory name (\$SOLRCLOUD_CONFIG)" ],
        "Z|zk|zkhost=s"      => [ \$zookeeper_ensemble,   "ZooKeeper ensemble for uploading / downloading SolrCloud configs (\$SOLR_ZOOKEEPER)" ],
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

if($progname =~ /collection|shard/){
    %options = (
        %options,
        %solroptions_collection,
        %solroptions_context,
    );
    if($progname =~ /commit_collection/){
        $commit_collection = 1;
    } elsif ($progname =~ /create_collection/) {
        $create_collection = 1;
        %options = (
            %options,
            %options_collection_opts,
        );
    } elsif ($progname =~ /empty_collection|truncate_collection/) {
        $truncate_collection = 1;
    } elsif ($progname =~ /delete_collection/) {
        $delete_collection = 1;
    } elsif ($progname =~ /reload_collection/) {
        $reload_collection = 1;
    } elsif ($progname =~ /split_shard/) {
        $split_shard = 1;
    } elsif ($progname =~ /split_shards/) {
        $split_shards = 1;
    }
} elsif ($progname =~ /config/) {
    if ($progname =~ /download_.*config/) {
        $download_config = 1;
    } elsif ($progname =~ /upload_.*config/) {
        $upload_config = 1;
    }
    %options = (
        %options,
        %options_solrcloud_config,
    );
} elsif ($progname =~ /reload_core/) {
    %options = (
        %options,
        %solroptions_core,
    );
    $reload_core = 1;
} else {
    $DESCRIPTION =~ s/Make sure/Best not to be called directly but instead via shorter symlinks found under the solr\/ directory that are easy to tab complete

Make sure/;

    %options = (
        %options,
        %solroptions_collection,
        %solroptions_core,
        %solroptions_context,
        "create-collection"         => [ \$create_collection,           "Create collection" ],
        "commit-collection"         => [ \$commit_collection,           "Commit collection" ],
        "truncate-collection"       => [ \$truncate_collection,         "Truncate collection" ],
        "delete-collection"         => [ \$delete_collection,           "Delete collection" ],
        "reload-collection"         => [ \$reload_collection,           "Reload collection" ],
        "reload-core"               => [ \$reload_core,                 "Reload core" ],
        #"split-shard=s"             => [ \$split_shard,                 "Split named shard that follows this arg, requires --collection" ],
        #"split-all-shards"          => [ \$split_all_shards,            "Split all shards for given collection" ],
        "download-config"           => [ \$download_config,             "Download config from ZooKeeper" ],
        "upload-config"             => [ \$upload_config,               "Upload config to ZooKeeper" ],
        %options_collection_opts,
        %options_solrcloud_config,
    );
}
if($options{"C|core=s"}){
    # change core short key to not clash with C|collection
    $options{"O|core=s"} = $options{"C|core=s"};
    delete $options{"C|core=s"};
}
splice @usage_order, 6, 0, qw/collection core create-collection create-collection-opts commit-collection truncate-collection delete-collection reload-collection reload-core split-shard split-all-shards download-config upload-config config-name zookeeper zk zkhost list-collections list-cores http-context/;

get_options();

if($create_collection + $commit_collection + $download_config + $truncate_collection + $delete_collection + $reload_collection + $reload_core + defined($split_shard) + $split_shards + $upload_config > 1){
    usage "cannot specify more than one action at a time";
}
unless($create_collection + $commit_collection + $download_config + $truncate_collection + $delete_collection + $reload_collection + $reload_core + defined($split_shard) + $split_shards + $upload_config == 1){
    usage "no action specified";
}

my $srcdir = abs_path(dirname(__FILE__));
my $env_file = "$srcdir/solr-env.sh";
( -f $env_file ) or $env_file = "$srcdir/solr/solr-env.sh";
if(-f $env_file ){
    my $fh = open_file $env_file;
    while(<$fh>){
        s/#.*//;
        /^\s*$/ and next;
        s/\s*export\s+//;
        if(/(\w+)\s*=\s*"?(.*?)"?\s*$/){
            vlog2 "loading env file =>  $1 = $2";
            $ENV{$1} = $2;
        }
    }
    vlog2;
} else {
    warn "solr-env.sh file not found in $srcdir or $srcdir/solr, not loading convenience environment variables\n";
}

env_creds("Solr");
env_vars("SOLR_COLLECTION",          \$collection);
env_vars("SOLR_COLLECTION_OPTS",     \$collection_opts);
env_vars("SOLR_CORE",                \$core);
env_vars("SOLR_HTTP_CONTEXT",        \$http_context);
env_vars("SOLR_ZOOKEEPER",           \$zookeeper_ensemble);
env_vars("SOLRCLOUD_CONFIG",         \$config_name);

my $zkcli="zkcli.sh";

if($upload_config or $download_config){
    if(defined($ENV{'ZKCLI_PATH'})){
        $zkcli = $ENV{'ZKCLI_PATH'};
        $zkcli =~ /\bzkcli.sh$/ or usage "invalid zkcli.sh path, does not end in zkcli.sh";
        $zkcli = validate_file($zkcli, 0, "zkcli");
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
        vlog_options "collection opts", $collection_opts;
    }
    $collection   = validate_solr_collection($collection) if $collection;
    $core         = validate_solr_core($core) if $core;
}

vlog2;
set_timeout();

unless($upload_config or $download_config){
    list_solr_collections();
    list_solr_cores();
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

sub solrcloud_defined(){
    defined($config_name)   or usage "solrcloud config name not defined";
    defined($zookeeper_ensemble) or usage "zookeeper ensemble not defined";
    plural scalar split(/\s*,\s*/, $zookeeper_ensemble);
}

sub core_defined(){
    defined($core) or usage "core not defined";
}

sub create_collection(){
    collection_defined();
    print "creating collection '$collection' at '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=CREATE&name=$collection" . ( $collection_opts ? "&$collection_opts" : "" );
}

sub delete_collection(){
    collection_defined();
    print "deleting collection '$collection' at '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=DELETE&name=$collection";
}

sub commit_collection(){
    collection_defined();
    print "committing collection '$collection' at '$host:$port'\n";
    curl_solr2 "$http_context/$collection/update/json?commit=true";
}

sub reload_collection(){
    collection_defined();
    print "reloading collection '$collection' at '$host:$port'\n";
    curl_solr2 "$solr_admin/collections?action=RELOAD&name=$collection";
}

sub reload_core(){
    core_defined();
    print "reloading core '$core' at '$host:$port'\n";
    curl_solr2 "$solr_admin/cores?action=RELOAD&name=$core";
}

sub truncate_collection(){
    collection_defined();
    print "truncating collection '$collection' at '$host:$port'\n";
    $ua->default_header("Content-type", "application/json");
    $json = curl_solr "$http_context/$collection/update/json", "POST", '{"delete": { "query":"*:*", "commitWithin":500 } }';
    print Dumper($json);
}

sub download_config(){
    solrcloud_defined();
    print "downloading SolrCloud ZooKeeper config '$config_name' from ZooKeeper$plural '$zookeeper_ensemble'\n";
    my @output = cmd("$zkcli -zkhost '$zookeeper_ensemble' -cmd downconfig -confdir '$config_name' -confname '$config_name'", 1);
    print join("\n", @output) . "\n";
}

sub upload_config(){
    collection_defined();
    solrcloud_defined();
    print "uploading SolrCloud ZooKeeper config '$config_name' to ZooKeeper$plural '$zookeeper_ensemble'\n";
    my @output = cmd("$zkcli -zkhost '$zookeeper_ensemble' -cmd upconfig -confdir '$config_name' -confname '$config_name'", 1);
    print join("\n", @output) . "\n";
    reload_collection;
}

create_collection()     if $create_collection;
commit_collection()     if $commit_collection;
download_config()       if $download_config;
truncate_collection()   if $truncate_collection;
delete_collection()     if $delete_collection;
reload_collection()     if $reload_collection;
reload_core()           if $reload_core;
split_shard()           if $split_shard;
split_all_shards()      if $split_all_shards;
upload_config()         if $upload_config;
