SysAdmin Tools
==============

A collection of Hadoop & Web Scale sysadmin tools I've written over the years that are generally useful across environments

### Setup ###

```
cd sysadmin
```
```
make
```

This will fetch my shared library submodule and also pull in the Perl CPAN module LWP::UserAgent (for which you'll need to be root)

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

watch_url.pl / watch_nginx_stats.pl require the LWP::UserAgent CPAN module:

Run as root:

```
cpan LWP::UserAgent
```

unidecode.pl requires the Text::Unidecode CPAN module:

```
cpan Text::Unidecode
```

You're now ready to use these programs.
