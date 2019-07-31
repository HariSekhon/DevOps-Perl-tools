#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2015-03-06 20:22:35 +0000 (Fri, 06 Mar 2015)
#

# Environment variables for solr_cli.pl and associated solr/ utility functions to avoid having to enter command line switches such as --collection

export SOLR_HOST="localhost"
export SOLR_PORT="8983"
export SOLR_COLLECTION="collection1"
export SOLR_CORE="collection1"
export SOLR_HTTP_CONTEXT="/solr"

# For creating new collection - should be in form key=value&key2=value2
#export SOLR_COLLECTION_OPTS="numShards=2&maxShardsPerNode=1&replicationFactor=2&dataDir=/data1/solr"
#
# usually requires at least numShards option
export SOLR_COLLECTION_OPTS="numShards=1"

# For uploading / downloading SolrCloud configs
#export SOLR_ZOOKEEPER="localhost:2181/solr"
export SOLR_ZOOKEEPER="localhost:2181"

# specify this to avoid zkCli.sh clash if on Mac which is case insensitive
#export ZKCLI_PATH="/usr/local/solr/example/scripts/cloud-scripts/zkcli.sh"

export SOLRCLOUD_CONFIG="myconf"

#export COLLECTION_ALIAS="ALL"
#export COLLECTIONS="collection1 collection2"
