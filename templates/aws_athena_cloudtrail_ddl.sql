--  vim:ts=4:sts=4:sw=4:et:filetype=sql
--
--  Author: Hari Sekhon
--  Date: [% DATE # 2020-01-01 15:38:58 +0000 (Wed, 01 Jan 2020) %]
--
--  [% URL %]
--
--  [% LICENSE %]
--
--  [% MESSAGE %]
--
--  [% LINKEDIN %]
--

-- replace <MY_BUCKET> and <MY_ACCOUNT_NUMBER> on last line

CREATE EXTERNAL TABLE cloudtrail_logs (
    eventversion STRING,
    useridentity STRUCT<
                   type:STRING,
                   principalid:STRING,
                   arn:STRING,
                   accountid:STRING,
                   invokedby:STRING,
                   accesskeyid:STRING,
                   userName:STRING,
    sessioncontext:STRUCT<
    attributes:STRUCT<
                   mfaauthenticated:STRING,
                   creationdate:STRING>,
    sessionissuer:STRUCT<
                   type:STRING,
                   principalId:STRING,
                   arn:STRING,
                   accountId:STRING,
                   userName:STRING>>>,
    eventtime STRING,
    eventsource STRING,
    eventname STRING,
    awsregion STRING,
    sourceipaddress STRING,
    useragent STRING,
    errorcode STRING,
    errormessage STRING,
    requestparameters STRING,
    responseelements STRING,
    additionaleventdata STRING,
    requestid STRING,
    eventid STRING,
    resources ARRAY<STRUCT<
                   ARN:STRING,
                   accountId:STRING,
                   type:STRING>>,
    eventtype STRING,
    apiversion STRING,
    readonly STRING,
    recipientaccountid STRING,
    serviceeventdetails STRING,
    sharedeventid STRING,
    vpcendpointid STRING
)
ROW FORMAT SERDE 'com.amazon.emr.hive.serde.CloudTrailSerde'
STORED AS INPUTFORMAT 'com.amazon.emr.cloudtrail.CloudTrailInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://<MY_BUCKET>/AWSLogs/<MY_ACCOUNT_NUMBER>/';
