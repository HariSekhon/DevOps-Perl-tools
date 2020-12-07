#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2013-09-29 23:49:14 +0100 (Sun, 29 Sep 2013)
#  Rewrite of shell version written on: 2009-03-16 09:53:29 2007 +0000 (Fri, 16 Mar 2009)
#
#  http://github.com/harisekhon/devops-perl-tools
#
#  License: see accompanying LICENSE file
#

# TODO: re-enable .m4 support, java not picking up .java.m4 only .java and not changing class NAME

# TODO: make it look for .ext, a.ext, a.b.ext etc

my $srcdir = dirname(__FILE__);
my $templatedir = "$srcdir/templates";
my @templatedirs = (
    # order is important - this is order of search / priority
    #                    - by searching adjacent repos first, we take the newest templates rather than the submodule's templates which are older
    "$srcdir/../k8s",
    "$srcdir/../kubernetes-templates",
    "$srcdir/../templates/kubernetes-templates",
    "$srcdir/../templates",
    "$srcdir/templates/kubernetes-templates",
    "$srcdir/templates",
    "$srcdir/../bash-tools",  # lots of awesome configs are stored in adjacent DevOps Bash tools repo which are even better than the generic templates submodule, but we don't want to override to more complicated huge Makefile rather than the template Makefile, so only use stuff from here if we haven't got a more generic template
    "$srcdir/bash-tools",
);

$DESCRIPTION = "Creates a new file of specified type with headers and code specific bits.

If only 1 script is specified then you will be dropped into your \$EDITOR on the file.

Supports any file extension types found under $srcdir/templates including:

c           C source
go          Golang program
py          Python
sql         SQL script
sh          Bash Shell script
rb          Ruby
pl          Perl
t           Perl test
pm          Perl module
bat         Batch file
js          JScript
vbs         VBS script
jsh         Java 11 script
groovy      Groovy script
scala       Scala main source
java        Java main source

build.gradle    Gradle template
build.sbt       SBT template
pom.xml         Maven template
yaml            YAML template

Makefile
Dockerfile
docker-compose.yml
Jenkinsfile
terraform / tf  (bundle of backend.tf, provider.tf, variables.tf, terraform.tfvars and main.tf)

file        Unix file
winfile     Windows file

If type is omitted, it is taken from the file extension, otherwise it defaults to unix file
";

$VERSION = "0.8.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use Carp;
use Cwd 'abs_path';
use File::Copy;
use File::Path 'make_path';
use File::Temp 'tempfile';
#use Mojo::Template;
use POSIX;
use Template;

$ENV{'PATH'} .= ':' . dirname(__FILE__) . '/../pytools';

my $comment = "#";
my @exe_types = qw/exp php pl py rb sh tcl/;

my $overwrite = 0;
my $noedit = 0;
my $filename;
my $ext;
my %vars;
my $plugin = 0;
my $lib    = 1;
my $puppet_module;

%options = (
    "o|overwrite"       => [ \$overwrite, "Overwrite file" ],
    "q|quick|n|no-edit" => [ \$noedit,    "Don't open \$EDITOR" ],
);

$usage_line = "usage: $progname [<type>] filename";
get_options();

scalar @ARGV == 1 or scalar @ARGV == 2 or usage;

my %vim_type_opts = (
    'c'    => '+-1',
    'doc'  => '-c normal$',
    'php'  => '+-2',
    # not needed without pod
    #'pl'   => '+/alarm',
    # set further down
    #'pl'   => '+12',
    'go'   => '+24 -c normal6l',
    'pp'   => '+11 -c normal6l',
    'py'   => '+20 -c normal$',
    'java' => '+-3 -c normal$',
    'sbt'  => '+24 -c stopinsert',
    'sh'   => '+25 -c stopinsert',
    'spec' => '+11 -c normal$',
    't'    => '+-2 -c normal$',
);

sub main(){
    parse();
    process_extension_logic();
    if($filename eq "terraform"
        or
       $filename eq "tf"){
       my @filenames = qw/backend.tf provider.tf variables.tf terraform.tfvars main.tf/;
       for my $filename (@filenames){
            my $template = get_template($filename, $ext);
            load_vars($filename, $template, $ext);
            create_templated_file($filename, $template, $ext);
        }
        $filename = \@filenames;
    } else {
        my $template = get_template($filename, $ext);
        load_vars($filename, $template, $ext);
        create_templated_file($filename, $template, $ext);
    }
    if($noedit){
        exit 0;
    } else {
        editor($filename, $ext);
    }

    # should not reach here chmod_open should be doing an exec
    die "UNKNOWN ERROR: hit end of code after chmod_open()";
}

main();

sub editor($$){
    my $filename = shift;
    my $type     = shift;
    my $vim_opts = "";
    $ENV{"EDITOR"} =~ /^([A-Za-z0-9-]+)$/;
    my $editor = $1;
    if($filename =~ /docker-compose.ya?ml/){
        $vim_opts .= "+18 -c normal7l";
    } elsif(defined($vim_type_opts{$type})){
        $vim_opts .= "$vim_type_opts{$type}";
    }
    if(not $editor){
        $editor="vim";
    }
    my $cmd = "$editor";
    if(ref($filename) eq 'ARRAY'){
        foreach(@$filename){
            $cmd .= " '$_'";
        }
        if($editor =~ /^vim?$/){
            $cmd .= " -O";
        }
    } else {
        if($editor =~ /^vim?$/){
            open(my $fh, $filename);
            @_=<$fh>;
            # only drop in to editing mode if the length of the template fits on the screen, otherwise you'd need to scroll upwards
            if($. < $ENV{"LINES"}){
                $cmd .= " + -c star $vim_opts";
            }
        }
        $cmd .= " '$filename'";
    }
    vlog2 $cmd;
    exec($cmd);
}

sub get_template($$){
    my $filename = shift;
    my $ext = shift;
    my $template;
    my @exts = ($ext);
    # check for templates of either file extension
    if($ext  =~ /^ya?ml$/){
        @exts = ("yml", "yaml");
    }

    my $base_filename = basename $filename;
    my $dirname = abs_path dirname $filename;

    # Special Rules
    if($dirname =~ /\/\.github\/workflows$/ and $ext =~ /^ya?ml$/){
        $base_filename = "github_workflow.yaml";
    } elsif($plugin and $ext eq "pl"){
        $base_filename = "template-plugin.pl";
    }

    # check each template directory for an exact match first at the most specific
    foreach my $templatedir (@templatedirs){
        # if we find a template file of the exact same name, eg. Makefile, Dockerfile, pom.xml, assembly.sbt etc. then copy as is
        foreach("$templatedir/$base_filename"){
            if(-f $_){
                return $_;
            }
        }
    }
    # next check for an exact template match with extension variations
    foreach my $templatedir (@templatedirs){
        foreach my $ext (@exts){
            my $base_filename_ext_variation = $base_filename;
            $base_filename_ext_variation =~ s/\.[^.]+$//;
            $base_filename_ext_variation .= ".$ext";
            my $template = "$templatedir/$base_filename_ext_variation";
            if(-f $template){
                return $template;
            }
        }
    }
    # next check for template.NAME.EXT
    foreach my $templatedir (@templatedirs){
        foreach my $ext (@exts){
            my $base_filename_ext_variation = $base_filename;
            $base_filename_ext_variation =~ s/\.[^.]+$//;
            $base_filename_ext_variation .= ".$ext";
            my $template = "$templatedir/template.$base_filename_ext_variation";
            if(-f $template){
                return $template;
            }
        }
    }
    # next check for template.EXT
    foreach my $templatedir (@templatedirs){
        foreach my $ext (@exts){
            my $template = "$templatedir/template.$ext";
            if(-f $template){
                return $template;
            }
        }
    }
    if (! $template or ! -e $template ){ #or -e "$template.m4")){
        if(scalar @ARGV == 2){
            die "ERROR: template for '$ext' type not found (couldn't find $template)"; # or $template.m4)"
        }
        $ext = "file";
        foreach my $templatedir (@templatedirs){
            my $template = "$templatedir/template.$ext";
            if (-f $template){
                return $template;
            }
        }
    }
    die "template could not be found" unless (defined($template) and -f $template);
}

sub create_templated_file($$$){
    my $filename = $_[0];
    my $template = $_[1];
    my $ext      = $_[2];
    #my %vars = %{$_[3]};
    #my $fh = open_file $template;
    #my $content = do { local $/; <$fh> };
    #close($fh);
    #my $mt = Mojo::Template->new;
    #my $output = $mt->render($content);
    vlog2 "creating file '$filename' from template '$template'";
    my $tt = Template->new(ABSOLUTE => 1);
    if (-f $filename){
        if(not $overwrite){
            die "$filename already exists, cannot create, aborting...\n"
        }
    } elsif(-e $filename){
        die "$filename already exists but is not a regular file!\n";
    }
    # To debug call without filename and will print to stdout instead
    #$tt->process($template, \%vars) or die $tt->error(), '\n';
    $tt->process($template, \%vars, $filename) or die $tt->error(), ' ';  # don't end in newline, give us this line number for debugging
    #open my $fh, ">", $filename or die "failed to open '$filename' for writing";
    #print $fh $output;
    #close($fh);
    chmod_check($filename, $ext);
    #if($ext eq "py"){
    #    system("cat '$filename'");
    #    exit;
    #}
}

sub chmod_check($$){
    my $filename = shift;
    my $type     = shift;
    my $mode = 0755;
    if(grep { $_ eq $type } @exe_types){
        vlog2 "chmod $mode";
        chmod $mode, $filename;
    }
}

# ============================================================================ #
#                                 P a r s i n g
# ============================================================================ #

sub parse(){
    if(scalar @ARGV == 1){
        $ext = $filename = $ARGV[0];
        $ext =~ s/^.*\///;
        $ext =~ s/^.*\.//;
        if(basename($filename) =~ /^(tf|terraform)$/){
            $ext = "tf";
        } elsif(basename(dirname(abs_path($filename))) eq "docs"){
            $ext = "doc";
        } elsif($ext eq $ARGV[0]){
            $ext = "file";
        }
    } elsif(scalar @ARGV == 2){
        $ext = $ARGV[0];
        $filename = $ARGV[1];
    } else {
        usage;
    }

    vlog_option "arg filename", $filename;
    vlog_option "arg ext",      $ext;

    $ext =~ /^([A-Za-z0-9]+)$/ or usage "invalid ext given";
    $ext = $1;

    if($ext eq "file" and $filename eq "sbt"){
        vlog2 "file 'sbt' detected, resetting filename to build.sbt";
        $filename = "build.sbt";
        $ext  = "sbt";
    }

    # doesn't work but not needed, if we find assembly.sbt in the template dir we use that
    #if($filename eq "assembly.sbt"){
    #    $ext = "assembly.sbt";
    #}

    $filename    = validate_filename($filename);
    #$templatedir = validate_directory($templatedir, "template dir", "noquit");
}

# ============================================================================ #
#                    E x t e n s i o n   P r o c e s s i n g
# ============================================================================ #

sub process_extension_logic(){
    if($filename eq "ppmod"){
        die "didn't specify module name/path after ppmod\n";
    }
    if($ext eq "ppmod"){
        vlog2 "ppmod";
        $ext = "pp";
        $filename =~ /((.*modules)\/([\w-]+))$/ or die "Failed to determine puppet module name, expecting modules/<name>\n";
        my $module_path = $1;
        my $modules_dir = $2;
        $puppet_module  = $3;
        (-d $modules_dir ) or die "modules dir $modules_dir not found\n";
        die "$module_path already exists\n" if(-e $module_path);
        make_path("$module_path/files", "$module_path/manifests", {$verbose => 1}) or die "Failed to create puppet $module_path/files and $module_path/manifests directories $!";
        $filename = "$module_path/manifests/init.pp";
    }

    my $base_filename = basename $filename;
    my $dirname = abs_path(dirname($filename));
    if(! -d $dirname){
        make_path($dirname, {$verbose => 1}) or die "Failed to create target directory '$dirname': $!";
    }

    if(grep { $ext eq $_ } qw/standalone solo plain simple/){
        vlog2 "standalone";
        $lib = 0;
        $ext = $ARGV[1];
        $ext =~ s/^.*\.//;
    } elsif($ext eq "plugin"){
        vlog2 "plugin";
        $plugin = 1;
        $ext = $ARGV[1];
        $ext =~ s/^.*\.//;
    } elsif($base_filename =~ /^check_/){
        vlog2 "implicit plugin check_";
        $plugin = 1;
    }
    # re-untaint ext
    $ext =~ /^([A-Za-z0-9]+)$/ or die "invalid ext found";
    $ext = $1;

    if($ext eq "pl"){
        if($plugin){
            $vim_type_opts{"pl"} = "'+normal 17G30|'";
        } elsif($lib){
            $vim_type_opts{"pl"} = "'+normal 16G17|'";
        }
    }
}

# ============================================================================ #
#                      T e m p l a t e   V a r i a b l e s
# ============================================================================ #

sub load_vars($$$){
    my $filename = $_[0];
    my $template = $_[1];
    my $ext = $_[2];
    my $base_filename = basename $filename;
    my $dirname = abs_path(dirname($filename));

    #if(-f "$template.m4" and which("m4")){
    #    vlog2 "m4 installed and template found: $template";
    my $name;
    if(basename($template) eq basename($filename)){
        $name = abs_path(dirname($filename));
    } else {
        $name = $filename;
    }
        $name = basename($name);
        if($ext eq "pm"){
            ($name = $filename) =~ s/\//::/g;
        }
        $name =~ s/\.$ext$//;
        vlog2 "name = $name";
        #my $env_cred = $name;
        #for($env_cred){
        for($name){
            #s/^check_//;
            #s/_[^_]+$//;
            s/[_-]/ /g;
            s/\b(.)/\u$1/g;
            s/ //g;
        }
    #    my $macros = "";
    #    $macros .= " -DLIB"    if $lib;
    #    $macros .= " -DPLUGIN" if $plugin;
    #    my $cmd = "m4 -DNAME='$name' -DENV_CRED='$env_cred' $macros -I '$templatedir' '$template.m4' > '$filename'";

    # filename is full path so regex end
    if($ext eq "sbt" or $filename =~ /pom.xml$/){
        $name = basename($dirname);
    }

    #inplace_edit($filename, 's/  Date:[^\r\n]*/  Date: ' . strftime('%F %T %z (%a, %d %b %Y)', localtime) . '/');
    my $date = strftime('%F %T %z (%a, %d %b %Y)', localtime);
    # Make this generic by detecting all .snippets or something and then iterating on them to replace %SNIPPET_NAME% from files
    #my $license_fh = open_file "$templatedir/license";
    #my $license = <$license_fh>;
    #close $license_fh;
    my @snippets = glob "$templatedir/snippet.*";
    my $snippet_name;
    my $snippet;
    my $fh;
    foreach(@snippets){
        ($snippet_name = uc basename $_) =~ s/^snippet\.//i;
        $snippet_name = validate_filename($snippet_name, undef, "snippet $snippet_name", 1);
        #$snippet = do { local $/; <{open_file($_)}> };
        $fh = open_file($_);
        $snippet = do { local $/; <$fh> };
        close($fh);
        chomp $snippet;
        $vars{$snippet_name} = $snippet;
    }
    $vars{"NAME"} = $name;
    $vars{"DATE"} = $date;
    # TODO: get this from git repo remote
    $vars{"URL"}  = "https://github.com/HariSekhon";
    if($ENV{"PWD"} =~ /playlists/){
        $vars{"URL"} .= "/Spotify-Playlists";
    } elsif($ENV{"PWD"} =~ /k8s$/){
        $vars{"URL"} .= "/kubernetes-templates";
    } elsif($plugin){
        $vars{"URL"} .= "/Nagios-Plugins";
    } elsif($base_filename eq "Dockerfile" or
            $base_filename eq "entrypoint.sh"){
        $vars{"URL"} .= "/Dockerfiles"
    } elsif($dirname =~ /\/github\//){
        my $basedir = $dirname;
        $basedir =~ s/.*\/github\///;
        $basedir =~ s/\/.*//;
        $vars{"URL"} .= "/$basedir";
    #} elsif($ext eq "sh"){
    #    $vars{"URL"} .= "/devops-bash-tools";
    #} elsif($ext eq "pl"){
    #    $vars{"URL"} .= "/devops-perl-tools";
    #} elsif($ext eq "py"){
    #    $vars{"URL"} .= "/devops-python-tools";
    #} elsif($ext eq "pm"){
    #    $vars{"URL"} .= "/lib";
    }
    if($ext eq "yaml"){
        # indent by 2 spaces not 4 for YAML
        $vars{"VIM_TAGS"} =~ s/4/2/g;
    }
    if($ext eq "py"){
        $vars{"MESSAGE"} =~ s/ and/\n#  and/;
    }
    $vars{"LINKEDIN"} = "https://www.linkedin.com/in/HariSekhon";
    #inplace_edit($filename, 's/\$URL.*\$/\$URL\$/; s/\$Id.*\$/\$Id\$/');
    #$? and die "Error: failed to set date: $!";
    foreach(sort keys %vars){
        vlog3 sprintf "snippet: %s => %s", $_, $vars{$_};
    }

    if($base_filename =~ /docker-compose.ya?ml/){
        $vars{"NAME"} =~ s/-?docker-compose-?//i;
        $vars{"NAME"} = lc $vars{"NAME"};
    }

    if(defined($puppet_module)){
        #inplace_edit($filename, "s/NAME/$puppet_module/g");
        $name = $puppet_module;
    }
}
