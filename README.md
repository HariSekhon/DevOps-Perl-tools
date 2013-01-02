SysAdmin Tools
==============

A collection of tools I've written over the years to ease systems administration tasks

### Setup ###
The first thing you need to do is to get my library submodule since I share code between this and other things that I have written over the years.

Enter the directory and run git submodule init and git submodule update to fetch my library repo:

```
cd nagios-plugins
```
```
git submodule init
```
```
git submodule update
```
This will pull in my git library repo which several of these plugins require to give very robust validation functions, utility functions, logging levels and debugging etc

You're now ready to use these programs.
