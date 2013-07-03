Hadoop & Web Scale SysAdmin Tools
=================================

A collection of Hadoop & Web Scale sysadmin tools I've written over the years that are generally useful across environments

### Setup ###

```
cd sysadmin
```
```
make
```

This will fetch my shared library submodule and also pull in the Perl CPAN modules LWP::UserAgent and Text::Unidecode (for which you'll need to be root)

#### OR: Manual Setup ####

Enter the directory and run git submodule init and git submodule update to fetch my library repo:

```
cd sysadmin
```
```
git submodule init
```
```
git submodule update
```

###### CPAN Modules ######

Install the following CPAN modules as root

For watch_url.pl / watch_nginx_stats.pl:

```
cpan LWP::UserAgent
```

For unidecode.pl:

```
cpan Text::Unidecode
```

You're now ready to use these programs.


### Jython for Hadoop Utils ###

A couple of the Hadoop utilities listed below require Jython (as well as Hadoop to be installed and correctly configured or course)

```
hadoop_hdfs_time_block_reads.jy
hadoop_hdfs_get_file_checksums.jy
```

Jython can be fetched from http://www.jython.org/downloads.html
