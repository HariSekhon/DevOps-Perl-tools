#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 6/8/2014
# 

# Quick Wrapper for IPython Notebook per user

# Intentionally no error handling or option handling. This suits my needs today

import os
import sys
import time
import getpass
from IPython.lib import passwd
from jinja2 import Template

dir = os.path.normpath(os.path.dirname(sys.argv[0]))

template_file = dir + "/ipython_notebook_config.py.tmpl"

template = Template(open(template_file).read())

password  = "1"
password2 = "2"

def get_password():
    global password
    global password2
    #password  = raw_input("Enter password to protect your personal IPython NoteBook\n\npassword: ")
    #password2 = raw_input("confirm password: ")
    print "Enter password to protect your personal IPython NoteBook\n"
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
    config.write(template.render(password = passwd(password), name = os.path.basename(sys.argv[0]), date = time.ctime(), template_path = os.path.abspath(template_file) ) )
    config.close()
    os.system("IPYTHON_OPTS='notebook --profile=nbserver' /opt/spark/bin/pyspark")
except KeyboardInterrupt:
    sys.exit(0)
