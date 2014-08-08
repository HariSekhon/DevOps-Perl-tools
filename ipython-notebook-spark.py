#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 6/8/2014
# 

# Quick Wrapper for IPython Notebook per user

# ipython and pyspark should be in your $PATH

# Intentionally no error handling or option handling. This suits my needs today

__author__  = "Hari Sekhon"
__version__ = "0.1"

import os
import sys
import time
import getpass
from IPython.lib import passwd
from jinja2 import Template

dir = os.path.abspath(os.path.dirname(sys.argv[0]))

template_file = dir + "/ipython_notebook_config.py.tmpl"

template = Template(open(template_file).read())

password  = "1"
password2 = "2"

# config goes in /root/.config/ipython/ not $HOME/.ipython for root - and this is a script for users should not be running as root
if getpass.getuser() == 'root':
    print "running as root is not supported, please use your regular user account"
    sys.exit(1)

def get_password():
    global password
    global password2
    #password  = raw_input("Enter password to protect your personal IPython NoteBook\n\npassword: ")
    #password2 = raw_input("confirm password: ")
    print "\nEnter a password to protect your personal IPython NoteBook (sha1 hashed and written to a config file)\n"
    password = getpass.getpass()
    password2 = getpass.getpass("Confirm Password: ")

try:
    get_password()
    while(password != password2):
        print "passwords do not match!\n"
        get_password()
    
    nbserver = os.environ["HOME"] + "/.ipython/profile_nbserver"
    
    if not os.path.exists(nbserver):
        os.system("ipython profile create nbserver")
    
    config = open(nbserver + "/ipython_notebook_config.py", "w")
    config.write(template.render(password = passwd(password), name = os.path.basename(sys.argv[0]), date = time.ctime(), template_path = template_file ) )
    config.close()
    os.system("IPYTHON_OPTS='notebook --profile=nbserver' pyspark")
    # don't hog the whole cluster in standalone mode, limit cores and possibly executor ram
    #os.system("MASTER=spark://master:7077 IPYTHON_OPTS='notebook --profile=nbserver' pyspark --total-executor-cores 20")
except KeyboardInterrupt:
    sys.exit(0)
