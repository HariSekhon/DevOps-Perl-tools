SysAdmin Tools
==============

A collection of tools I've written over the years to ease systems administration tasks

### Setup ###

Run

```
cd sysadmin
```
```
make
```

This will fetch my shared library submodule and also pull in the Perl CPAN module LWP::UserAgent (for which you'll need to be root)

## Manual Setup ##

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

The LWP::UserAgent Perl module is also needed for watch_url.pl and watch_nginx_stats.pl

```
sudo cpan LWP::UserAgent
```

You're now ready to use these programs.
