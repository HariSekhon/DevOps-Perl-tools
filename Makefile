#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon/toolbox
#
#  License: see accompanying LICENSE file
#

ifdef TRAVIS
    SUDO2 =
else
    SUDO2 = sudo
endif

# EUID /  UID not exported in Make
ifeq '$(USER)' 'root'
    SUDO =
    SUDO2 =
else
    SUDO = sudo
endif

.PHONY: make
make:
	[ -x /usr/bin/apt-get ] && make apt-packages || :
	[ -x /usr/bin/yum ]     && make yum-packages || :

	git submodule init
	git submodule update

	cd lib && make

	# don't track and commit your personal name, company name etc additions to scrub_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged scrub_custom.conf
	git update-index --assume-unchanged solr/solr-env.sh

	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	# Module::CPANfile::Result and Module::Install::Admin are needed for Hijk which is auto-pulled by Search::Elasticsearch but doesn't auto-pull Module::CPANfile::Result

	# workaround for broken pod coverage tests
	#yes | $(SUDO) cpan --force XML::Validate || :

	yes | $(SUDO2) cpan \
		CAM::PDF \
		JSON \
		JSON::XS \
		LWP::Simple \
		LWP::UserAgent \
		Net::LDAP \
		Net::LDAPI \
		Net::LDAPS \
		Module::CPANfile::Result \
		Module::Install::Admin \
		Search::Elasticsearch \
		Term::ReadKey \
		Text::Unidecode \
		Time::HiRes \
		XML::LibXML \
		XML::Validate \
		|| :
#		IO::Socket::SSL \
#		Net::LDAP::Filter \
	easy_install -U setuptools || :
	$(SUDO) easy_install pip || :
	$(SUDO) pip install jinja2 || :

.PHONY: apt-packages
apt-packages:
	$(SUDO) apt-get install -y gcc || :
	# needed to fetch the library submodule at end of build
	$(SUDO) apt-get install -y git || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	$(SUDO) apt-get install -y libssl-dev || :
	# needed to build XML::LibXML
	$(SUDO) apt-get install -y libxml2-dev || :
	$(SUDO) apt-get install -y ipython-notebook || :
	dpkg -l python-setuptools python-dev &>/dev/null || $(SUDO) apt-get install -y python-setuptools python-dev || :

.PHONY: yum-packages
yum-packages:
	rpm -q gcc || $(SUDO) yum install -y gcc || :
	# needed to fetch the library submodule and CPAN modules
	rpm -q perl-CPAN git || $(SUDO) yum install -y perl-CPAN git || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	rpm -q openssl-devel || $(SUDO) yum install -y openssl-devel || :
	# needed to build XML::LibXML
	rpm -q libxml2-devel || $(SUDO) yum install -y libxml2-devel || :
	rpm -q ipython-notebook || $(SUDO) yum install -y ipython-notebook || :
	rpm -q python-setuptools python-pip python-devel || $(SUDO) yum install -y python-setuptools python-pip python-devel || :

.PHONY: test
test:
	cd lib && make test
	# doesn't return a non-zero exit code to test
	#for x in *.pl; do perl -T -c $x; done
	# TODO: add more functional tests back in here
	tests/help.sh

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH"

.PHONY: update
update:
	make update2
	make
	make test

.PHONY: update2
update2:
	git pull
	git submodule update
