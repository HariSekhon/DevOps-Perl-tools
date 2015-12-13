#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon/tools
#
#  License: see accompanying LICENSE file
#

ifdef PERLBREW_PERL
	SUDO2 =
	CPANM = cpanm
else
	SUDO2 = sudo
	CPANM = /usr/local/bin/cpanm
endif

# EUID /  UID not exported in Make
# USER not populated in Docker
ifeq '$(shell id -u)' '0'
	SUDO =
	SUDO2 =
else
	SUDO = sudo
endif

.PHONY: make
make:
	if [ -x /usr/bin/apt-get ]; then make apt-packages; fi
	if [ -x /usr/bin/yum ];     then make yum-packages; fi

	git submodule init
	git submodule update

	cd lib && make

	# don't track and commit your personal name, company name etc additions to scrub_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged scrub_custom.conf
	git update-index --assume-unchanged solr/solr-env.sh

	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	# Module::CPANfile::Result and Module::Install::Admin are needed for Hijk which is auto-pulled by Search::Elasticsearch but doesn't auto-pull Module::CPANfile::Result

	# workaround for broken pod coverage tests
	#yes | $(SUDO) cpan --force XML::Validate

	# auto-configure cpan for Perl 5.8 which otherwise gets stuck prompting for a region for downloads
	#(echo y;echo o conf prerequisites_policy follow;echo o conf commit) | cpan
	yes "" | $(SUDO2) cpan App::cpanminus
	yes "" | $(SUDO2) $(CPANM) --notest \
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
		;
#		IO::Socket::SSL \
#		Net::LDAP::Filter \
	easy_install -U setuptools
	#$(SUDO) easy_install pip
	#$(SUDO) pip install jinja2
	@echo
	@echo BUILD SUCCESSFUL

.PHONY: apt-packages
apt-packages:
	$(SUDO) apt-get install -y gcc
	# needed to fetch the library submodule at end of build
	$(SUDO) apt-get install -y git
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	$(SUDO) apt-get install -y libssl-dev
	# needed to build XML::LibXML
	$(SUDO) apt-get install -y libxml2-dev
	#$(SUDO) apt-get install -y ipython-notebook
	#dpkg -l python-setuptools python-dev &>/dev/null || $(SUDO) apt-get install -y python-setuptools python-dev

.PHONY: yum-packages
yum-packages:
	rpm -q gcc || $(SUDO) yum install -y gcc
	# needed to fetch the library submodule and CPAN modules
	rpm -q perl-CPAN git || $(SUDO) yum install -y perl-CPAN git
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	rpm -q openssl-devel || $(SUDO) yum install -y openssl-devel
	# needed to build XML::LibXML
	rpm -q libxml2-devel || $(SUDO) yum install -y libxml2-devel
	# python-pip requires EPEL, so try to get the correct EPEL rpm - for Make must escape the $3
	rpm -ivh "https://dl.fedoraproject.org/pub/epel/epel-release-latest-`awk '{print substr($$3, 0, 1); exit}' /etc/*release`.noarch.rpm"
	#rpm -q python-setuptools python-pip python-devel || $(SUDO) yum install -y python-setuptools python-pip python-devel
	#rpm -q ipython-notebook || $(SUDO) yum install -y ipython-notebook

.PHONY: test
test:
	cd lib && make test
	# doesn't return a non-zero exit code to test
	#for x in *.pl; do perl -T -c $x; done
	# TODO: add more functional tests back in here
	tests/all.sh

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
	git submodule update --init
