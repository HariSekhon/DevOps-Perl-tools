#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 6/8/2014
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# Quick Wrapper for IPython Notebook per user
#
# Tested on Spark 1.0.x on Hortonworks 2.1 (Yarn + Standalone) and IBM BigInsights 2.1.2 (Standalone)
#
# IPython and PySpark should be in your $PATH
#
# Intentionally omitting option parsing and error handling. This suits my needs today

# Make sure to set these, I set sane defaults below
#
# export YARN_CONF_DIR=/etc/hadoop/conf
# export PATH="$PATH:/opt/spark/bin"

__author__  = "Hari Sekhon"
__version__ = "0.2"

import getpass
import glob
import os
import re
import shutil
import sys
import time
from IPython.lib import passwd
from jinja2 import Template

dir = os.path.abspath(os.path.dirname(sys.argv[0]))

###########################
# PySpark Settings
#
# host of standalone spark master daemon - only for standalone cluster mode
spark_master      = "master"
spark_master_port = 7077
# used for both standalone and Yarn client
num_executors   = 5
executor_cores  = 2
executor_memory = "10g"

SPARK_HOME = os.getenv('SPARK_HOME', None)
if SPARK_HOME:
    os.environ['PATH'] = "%s:%s/bin" % (os.getenv("PATH", ""), SPARK_HOME)
else:
    print "SPARK_HOME needs to be set (eg. export SPARK_HOME=/opt/spark)"
    sys.exit(3)

# Workaround to assembly jar not providing pyspark on Yarn and PythonPath not being passed through normally
#
# Error from python worker:
#  /usr/bin/python: No module named pyspark
# PYTHONPATH was:
#  /data1/hadoop/yarn/local/usercache/hari/filecache/14/spark-assembly-1.0.2-hadoop2.4.0.jar
#
# this isn't enough because the PYTHONPATH isn't passed through to Yarn - also it's set my pyspark wrapper anyway
# so this is actually to generate SPARK_YARN_USER_ENV which allows the pyspark to execute across the cluster
# this will probably get fixed up and be unneccessary in future
#os.environ['PYTHONPATH'] = os.getenv('PYTHONPATH', '') + ":%s/python" % SPARK_HOME
sys.path.insert(0, os.path.join(SPARK_HOME, 'python'))
for lib in glob.glob(os.path.join(SPARK_HOME, 'python/lib/py4j-*-src.zip')):
    sys.path.insert(0, lib)
#
# simply appending causes an Array error in Java due to the first element being empty if SPARK_YARN_USER_ENV isn't already set
if os.getenv('SPARK_YARN_USER_ENV', None):
    os.environ['SPARK_YARN_USER_ENV'] = os.environ['SPARK_YARN_USER_ENV'] + ",PYTHONPATH=" + ":".join(sys.path)
else:
    os.environ['SPARK_YARN_USER_ENV'] = "PYTHONPATH=" + ":".join(sys.path)

# Set some sane likely defaults
if not (os.getenv('HADOOP_CONF_DIR', None) or os.getenv('YARN_CONF_DIR', None)):
    print "warning: YARN_CONF_DIR not set, temporarily setting /etc/hadoop/conf"
    os.environ['YARN_CONF_DIR'] = '/etc/hadoop/conf'

if not os.getenv('MASTER', None):
    # Convenient Default to save users having to specify
    # local mode - default anyway
    #os.environ['MASTER'] = "local[2]"
    # standalone master mode
    #os.environ['MASTER'] = spark://%s:%s" % (spark_master, spark_master_port)
    # Yarn mode - this is what I use now on Hortonworks
    # PYSPARK_SUBMIT_ARGS doesn't work for --master
    #os.environ['PYSPARK_SUBMIT_ARGS'] = "--master yarn --deploy-mode yarn_client"
    os.environ['MASTER'] = "yarn_client"
    
if not os.getenv('PYSPARK_SUBMIT_ARGS', None):
    # don't hog the whole cluster - limit executor / RAM / CPU usage
    os.environ['PYSPARK_SUBMIT_ARGS'] = "--num-executors %d --total-executor-cores %d --executor-memory %s" % (num_executors, executor_cores, executor_memory)

###########################
# IPython Notebook Settings
template_file       = dir + "/.ipython-notebook-pyspark.ipython_notebook_config.py.j2"
pyspark_startup_src = dir + "/.ipython-notebook-pyspark.00-pyspark-setup.py"

# Set default to 0.0.0.0 for portability but better set to your IP
# for IPython output to give the correct URL to users
default_ip = "0.0.0.0"

# try setting to the main IP with default gw to give better feedback to user where to connect
ip = os.popen("ifconfig $(netstat -rn | awk '/^0.0.0.0[[:space:]]/ {print $8}') | sed -n '2 s/.*inet addr://; 2 s/ .*// p'").read().rstrip('\n')
if not re.match('^\d+\.\d+\.\d+\.\d+$', ip):
    ip = default_ip

ipython_profile_name = "pyspark"
###########################


template = Template(open(template_file).read())

password  = "1"
password2 = "2"

if getpass.getuser() == 'root':
    print "please run this as your regular user account and not root!"
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
    ipython_profile         = os.popen("ipython locate").read().rstrip("\n") + "/profile_%s" % ipython_profile_name
    ipython_notebook_config = ipython_profile + "/ipython_notebook_config.py"
    passwd_txt              = ipython_profile + "/passwd.txt"
    setup_py                = ipython_profile + "/startup/00-pyspark-setup.py"

    if not os.path.exists(ipython_profile):
        print "creating new ipython notebook profile"
        cmd = "ipython profile create %s" % ipython_profile_name
        #print cmd
        os.system(cmd)

    if not os.path.exists(passwd_txt):
        get_password()
        while(password != password2):
            print "passwords do not match!\n"
            get_password()
        print "writing new encrypted password"
        passwd_fh = open(passwd_txt, "w")
        passwd_fh.write(passwd(password))
        passwd_fh.close()
        os.chmod(passwd_txt, 0600)
    
    # really only useful for local mode spark, doesn't support YARN at this time
    if not os.path.exists(setup_py):
        shutil.copy(pyspark_startup_src, setup_py)
        os.chmod(setup_py, 0600)
 
    if not os.path.exists(ipython_notebook_config) or passwd_txt not in open(ipython_notebook_config).read():
        print "writing new ipython notebook config"
        config = open(ipython_notebook_config, "w")
        #config.write(template.render(password = passwd(password), ip = ip, name = os.path.basename(sys.argv[0]), date = time.ctime(), template_path = template_file ) )
        config.write(template.render(passwd_txt = passwd_txt, ip = ip, name = os.path.basename(sys.argv[0]), date = time.ctime(), template_path = template_file ) )
        config.close()
        os.chmod(ipython_notebook_config, 0600)
    #cmd = "IPYTHON_OPTS='notebook --profile=%s' PYSPARK_SUBMIT_ARGS='%s' pyspark --master yarn_client" % (ipython_profile_name, os.getenv("PYSPARK_SUBMIT_ARGS", ""))
    cmd = "IPYTHON_OPTS='notebook --profile=%s' pyspark" % ipython_profile_name
    #print "MASTER=%s\nPYSPARK_SUBMIT_ARGS=%s" % (os.environ['MASTER'], os.environ['PYSPARK_SUBMIT_ARGS'])
    #print cmd
    os.system(cmd)
except KeyboardInterrupt:
    sys.exit(0)
