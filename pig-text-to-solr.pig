--
--  Author: Hari Sekhon
--  Date: 2015-03-12 22:49:01 +0000 (Thu, 12 Mar 2015)
--
--  vim:ts=4:sts=4:sw=4:et
--

-- Pig script to index text files or logs for fast source file lookups in SolrCloud

-- Tested on Pig 0.14 on Tez via Hortonworks HDP 2.2

-- https://docs.lucidworks.com/display/lweug/Using+Pig+with+LucidWorks+Search

REGISTER 'hadoop-lws-job.jar';
register 'pig-udfs.jy' using jython as hari;

--%default path '/data';
--%default collection 'collection1';
--%default zkhost 'localhost:2181';

-- use zkhost for SolrCloud, it's more efficient to skip first hop using client side logic and also it's more highly available
--set solr.zkhost $zkhost;

-- use solrUrl only for standard old standalone Solr
--set solr.solrUrl $solrUrl;

--set solr.collection $collection;
--%declare solr.collection $collection;

-- for file-by-file as one doc each but doesn't scale
--set lww.buffer.docs.size 1;

set lww.buffer.docs.size 1000;
set lww.commit.on.close true;

set mapred.map.tasks.speculation.execution false;
set mapred.reduce.tasks.speculation.execution false;

lines  = load '$path' using PigStorage('\n', '-tagPath') as (path:chararray, line:chararray);
-- this causes out of heap errors in Solr because some files may be too large to handle this way - it doesn't scale 
--lines2 = foreach (group lines by path) generate $0 as path, BagToString($1, ' ') as line:chararray;
--lines_final = foreach lines2 generate UniqueId() as id, 'path_s', path, 'line_s', line;

lines2 = filter lines by line is not null;

-- no point storing redundant prefixes like hdfs://nameservice1 of file: the same bytes over and over
--lines3 = foreach lines2 generate REPLACE(path, '^file:', '') as path, line;
lines3 = foreach lines2 generate REPLACE(path, '^hdfs://\\w+(?::\\d+)?', '') as path, line;
-- order by path asc -- to force a sort + shuffle -- to find out if the avg requests per sec are being held back by the mapper phase decompressing bz2 files or something else by forcing a reduce phase

-- going back to using suffixed Solr fields in case someone hasn't configured their schema properly they should be able to fall back on dynamicFields

-- since the lines in the file may not be unique was considering using a uuid
-- can use UniqueId() from Pig 0.14
lines_final = foreach lines3 generate CONCAT(path, '|', hari.md5_uuid(line)) as id, 'path_s', path, 'line_s', line;


store lines_final into 'IGNORED' using com.lucidworks.hadoop.pig.SolrStoreFunc();
