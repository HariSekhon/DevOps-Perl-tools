#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-10-16 19:05:27 +0100 (Wed, 16 Oct 2013)
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

# TODO: rewrite with native XML parsing

$DESCRIPTION = "Diff 2 XML files or URLs' XML by first converting them to name=value pairs via XSLT, sorting the results and then diffing that.

Very useful for comparing the configuration of 2 Hadoop clusters from their '/conf' URLs.


Credit to my colleague Esteban Gutierrez @ Cloudera who provided the original XSLT command line idea:

diff <(curl 'http://cluster1:port/conf' | xsltproc configuration.xsl - | sort) <(curl 'http://cluster2:port/conf' | xsltproc configuration.xsl - | sort)


Improvements:

Breaks this process down into multiple stages, validates at each stage so you don't end up with a blank or one sided diff on silent failures in the pipeline:

1. Reads XML from file or URL, then validates it (catches blank/malformed XML)
2. Does transformation using xsltproc, then validates we have key=value pairs to diff (catches xsltproc failure returning blank output)
3. Finally sorts and passes to diff

Limitations:

Slurps the whole of both XML files or URLs in to memory for XML validating purposes to catch broken XML rather than silently failing and resulting in a one sided or worse blank diff (hard to spot you may think the 2 XMLs are equal in that case). Don't abuse this against massive files or you'll run out of memory.

Multi-line values are not supported at this time.
 ";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use File::Temp 'tempfile';
use LWP::Simple '$ua';
use XML::Validate;
#use FileHandle;
#use IPC::Open2;

set_timeout_default(30);

$usage_line = "
usage: $progname filename1.xml filename2.xml [optional.xsl]

       $progname http://host1:port/conf.xml http://host2:port/conf.xml [optional.xsl]

       $progname filename1.xml http://host2:port/conf.xml [optional.xsl]

Optional 3rd argument can be XSL transformation file, defaults to using 'xml-diff.xsl' in same directory as this program.";

get_options();

scalar @ARGV > 1 or usage "must supply at least 2 arguments for files or URLs";
my $xml_path1 = $ARGV[0];
my $xml_path2 = $ARGV[1];

my $xsl_path;
if(scalar @ARGV == 2){
    $xsl_path = dirname(__FILE__) . "/xml-diff.xsl";
} elsif(scalar @ARGV == 3){
    $xsl_path = $ARGV[2];
} else {
    usage "wrong number of args given, should be 2 xml files or URLs and an optional xsl configuration file";
}

$xsl_path = validate_file($xsl_path, "xsl file");

vlog2;
set_timeout();

my $validator = new XML::Validate(Type => "LibXML");

$ua->agent("Hari Sekhon $progname $main::VERSION");

my %source;
sub get_xml($){
    my $xml_path = shift;
    defined($xml_path) or die "no xml path passed to get_xml()";
    if(isUrl($xml_path)){
        $source{$xml_path} = "URL";
        return curl $xml_path;
    } else {
        $source{$xml_path} = "file";
        $xml_path = validate_file($xml_path);
        my $fh = open_file $xml_path;
        return join("\n", <$fh>);
    }
}

sub validate_xml($$){
    my $string = shift;
    my $name   = shift;
    vlog2 "validating xml from $name";
    vlog3 "XML string: '$string'";
    # XXX: this seems to error out instead of returning something that I can handle :-/
    if($validator->validate($string)){
        vlog2 "valid xml contents for $name";
    } else {
        my $message = $validator->last_error()->{message};
        my $line    = $validator->last_error()->{line};
        my $column  = $validator->last_error()->{column};
        die "Error: invalid XML read from $name: $message at line $line, column $column\n";
    }
}

sub xsltproc($){
    my $xml_path = shift;
# This doesn't work due to buffering
#    my $pid = open2( \*Reader, \*Writer, "xsltproc '$xsl_path' - | sort" );
#    Writer->autoflush();
#    # validation done before calling this sub, not doing more here
#    #open my $fh, "| xsltproc '$xsl_path' - | sort |" or die "Failed to execute xsltproc for $name contents\n";
#    print Writer $xml_string or die "Failed to pipe in to xslt for $name contents\n";
#    my $tokenized_xml = <Reader>;
#    Writer->close();
#    Reader->close();
#    $tokenized_xml =~ /^\s*$/ and die "got back blank output from xlstproc for $name contents\n";
#    return $tokenized_xml;
    my $tokenized_xml = "";
    open my $fh, "xsltproc '$xsl_path' '$xml_path' |";
    while(<$fh>){
        # This breaks on multi-line XML like core-site.xml hadoop.security.auth_to_local RULEs
        #unless(/^\s*(.*=.*)?\s*$/){
        #chomp $_;
        #die "Failed basic line validation on xlstproc output from '$xml_path', got '$_' instead of key=value pair\n";
        #}
        $tokenized_xml .= $_;
    }
    if($tokenized_xml =~ /^\s*$/){
        die "failed to tokenize xml for $xml_path, empty xsltproc output detected '$tokenized_xml'\n";
    }
    return $tokenized_xml;
}

my $xml_contents1 = get_xml($xml_path1);
validate_xml($xml_contents1, "$source{$xml_path1} 1");
vlog2;

my $xml_contents2 = get_xml($xml_path2);
validate_xml($xml_contents2, "$source{$xml_path2} 2");
vlog2;

sub write_temp($){
    my $string = shift;
    defined($string) or die "undefined string passed to write_temp()\n";
    $string =~ /^\s*$/ and die "blank output found in intermediate stage, passed to write_temp(), may indicate a failure in the processing pipeline\n";
    my ( $fh, $filename ) = tempfile();
    vlog2 "writing output to $filename";
    print $fh $string or die "Failed to write to temp file '$filename'\n";
    close $fh or die "Failed to close file handle to temp file '$filename'\n";
    return $filename;
}

# Did used to have logic to not re-write out the XML if source was file but no real harm in doing this and prevents any modification to the original file since we read and validated it from being an issue, also since we can't predict the location of this temp file it's less likely to get messed with
my $xml_temp1 = write_temp($xml_contents1);
my $xml_temp2 = write_temp($xml_contents2);

$xml_temp1 = validate_file($xml_temp1, undef, undef, 1);
$xml_temp2 = validate_file($xml_temp2, undef, undef, 1);

my $xml_kv1 = write_temp(xsltproc($xml_temp1));
my $xml_kv2 = write_temp(xsltproc($xml_temp2));

my $sorted_file1 = write_temp(`sort '$xml_kv1'`);
my $sorted_file2 = write_temp(`sort '$xml_kv2'`);

( -z $sorted_file1 ) and die "sorted file 1 '$sorted_file1' is empty, nothing to diff (may be a failure in the processing pipeline)\n";
( -z $sorted_file2 ) and die "sorted file 2 '$sorted_file2' is empty, nothing to diff (may be a failure in the processing pipeline)\n";
vlog2;
my $cmd = "bash -c 'diff \"$sorted_file1\" \"$sorted_file2\"'";
vlog2($cmd);
system($cmd);

vlog2;
sub unlink_tmp($){
    my $tmp = shift;
    vlog2 "unlinking $tmp";
    unlink $tmp or warn "failed to unlink '$tmp': $!\n";
}
unlink_tmp($xml_temp1);
unlink_tmp($xml_temp2);
unlink_tmp($xml_kv1);
unlink_tmp($xml_kv2);
unlink_tmp($sorted_file1);
unlink_tmp($sorted_file2);
