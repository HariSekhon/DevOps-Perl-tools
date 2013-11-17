Hadoop & Web Scale SysAdmin Tools
=================================

A few of Hadoop & Web Scale sysadmin tools I've written over the years that are generally useful across environments

### Setup ###

The 'make' command will initialize my library submodule then use 'sudo' to install the required CPAN modules

```
git clone https://github.com/harisekhon/sysadmin
cd sysadmin
make
```

#### OR: Manual Setup ####

Enter the sysadmin directory and run git submodule init and git submodule update to fetch my library repo and then install the CPAN modules as mentioned further down:

```
git clone https://github.com/harisekhon/sysadmin
cd sysadmin
git submodule init
git submodule update
```

Then proceed to install the CPAN modules below by hand

###### CPAN Modules ######

Install the following CPAN modules using the cpan command, use sudo if you're not root:

```
sudo cpan LWP::Simple LWP::UserAgent Text::Unidecode Time::HiRes XML::Validate
```

You're now ready to use these programs.


### Jython for Hadoop Utils ###

A couple of the Hadoop utilities listed below require Jython (as well as Hadoop to be installed and correctly configured or course)

```
hadoop_hdfs_time_block_reads.jy
hadoop_hdfs_get_file_checksums.jy
```

Jython is a simple download and unpack and can be fetched from http://www.jython.org/downloads.html

Then add the Jython untarred directory to the $PATH or specify the /path/to/jython_dir/bin/jython explicitly:

```
/path/to/jython-x.y.z/bin/jython -J-cp `hadoop classpath` hadoop_hdfs_time_block_reads.jy --help
```

The ```-J-cp `hadoop classpath```` bit does the right thing in finding the Hadoop java classes required to use the Hadoop APIs.
