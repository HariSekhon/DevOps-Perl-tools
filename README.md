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

#### Manual Setup ####

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

##### CPAN Modules #####

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
