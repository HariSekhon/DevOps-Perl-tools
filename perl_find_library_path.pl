#!/usr/bin/perl
# Don't use -T taint mode here as it ignores $PERL5LIB - allow -T on the CLI to compare the difference whereas -T here takes away that option
#
#  Author: Hari Sekhon
#  Date: 2019-09-27
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

$DESCRIPTION = "

Simple tool to print the local path to one or more libraries given as arguments

Useful for finding where things are installed on different operating systems like Mac vs Linux

If no libraries are specified, finds the default library location via File::Basename

Tested on Perl 5.x on Mac and Linux

";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}

sub usage_local(){
    # doing this as a sub has a prototype mismatch if you import anything that has the same sub name, eg. usage() from HariSekhonUtils.pm
    #usage;
    my $progname = basename $0;
    my $description = $main::DESCRIPTION;
    $description =~ s/^\s*//;
    $description =~ s/\s*$//;
    print "$description\n\n\n";
    print "usage: $progname <library1> [<library2> <library3>...]\n\n";
    exit 3;

}

my $exitcode = 0;

foreach my $module (@ARGV){
    if($module =~ /^-/){
        usage_local();
    }
}

sub get_module_path($){
    #$module =~ /^([A-Za-z0-9:]+)$/ or next
    my $module = shift;
    $module =~ /^([\w:]+)$/ or die "Failed module regex regex validation for $module";
    $module = $1;
    my $path = $module;
    $path =~ s/::/\//g;
    # normalize between adding .pm or omitting it for each module
    $path =~ s/.pm$//;
    $path =~ s/$/.pm/;
    $path =~ /^([\w.\/]+)$/ or die "Failed path regex regex validation for $path";
    $path = $1;
    eval {
        require $path;
        import $module;
    };
    if($@){
        print STDERR  "perl module '$module' not found: $@";
        $exitcode = 2;
        return;
    }
    if(exists $INC{$path}){
        return "$INC{$path}";
    } else {
        $exitcode = 3;
    }
}

if(@ARGV){
    foreach my $module (@ARGV){
        my $path = get_module_path($module);
        if(defined($path)){
            print "$path\n";
        }
    }
} else {
    my $path = get_module_path("File::Basename");
    $path =~ s/\/File\/Basename.pm//;
    print "$path\n";
}

exit $exitcode
