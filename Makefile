#  vim:ts=4:sts=4:sw=4:noet
#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

export PATH := $(PATH):/usr/local/bin

CPANM = cpanm

ifneq ("$(PERLBREW_PERL)$(TRAVIS)", "")
	SUDO2 =
else
	SUDO2 = sudo
endif

# EUID /  UID not exported in Make
# USER not populated in Docker
ifeq '$(shell id -u)' '0'
	SUDO =
	SUDO2 =
else
	SUDO = sudo
endif

.PHONY: build
build:
	if [ -x /usr/bin/apt-get ]; then make apt-packages; fi
	if [ -x /usr/bin/yum ];     then make yum-packages; fi

	git submodule init
	git submodule update --recursive

	cd lib && make

	# don't track and commit your personal name, company name etc additions to scrub_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged scrub_custom.conf
	git update-index --assume-unchanged solr/solr-env.sh

	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	# Module::CPANfile::Result and Module::Install::Admin are needed for Hijk which is auto-pulled by Search::Elasticsearch but doesn't auto-pull Module::CPANfile::Result

	# workaround for broken pod coverage tests
	#yes | $(SUDO) cpan --force XML::Validate

	# auto-configure cpan for Perl 5.8 which otherwise gets stuck prompting for a region for downloads
	# this doesn't work it's misaligned with the prompts, should use expect instead if I were going to do this
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
	@echo "BUILD SUCCESSFUL (tools)"

.PHONY: apt-packages
apt-packages:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y gcc
	# needed to fetch the library submodule at end of build
	$(SUDO) apt-get install -y git
	$(SUDO) apt-get install -y wget
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	$(SUDO) apt-get install -y libssl-dev
	# needed to build XML::LibXML
	$(SUDO) apt-get install -y libxml2-dev
	#$(SUDO) apt-get install -y ipython-notebook
	#dpkg -l python-setuptools python-dev &>/dev/null || $(SUDO) apt-get install -y python-setuptools python-dev

.PHONY: yum-packages
yum-packages:
	rpm -q gcc || $(SUDO) yum install -y gcc
	rpm -q git || $(SUDO) yum install -y git
	rpm -q wget || $(SUDO) yum install -y wget
	# needed to fetch the library submodule and CPAN modules
	rpm -q perl-CPAN git || $(SUDO) yum install -y perl-CPAN git
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	rpm -q openssl-devel || $(SUDO) yum install -y openssl-devel
	# needed to build XML::LibXML
	rpm -q libxml2-devel || $(SUDO) yum install -y libxml2-devel
	# python-pip requires EPEL, so try to get the correct EPEL rpm
	rpm -q epel-release || yum install -y epel-release || { wget -O /tmp/epel.rpm "https://dl.fedoraproject.org/pub/epel/epel-release-latest-`grep -o '[[:digit:]]' /etc/*release | head -n1`.noarch.rpm" && $(SUDO) rpm -ivh /tmp/epel.rpm && rm -f /tmp/epel.rpm; }
	rpm -q python-setuptools python-pip python-devel || $(SUDO) yum install -y python-setuptools python-pip python-devel
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
	make update-no-recompile

.PHONY: update-no-recompile
update-no-recompile:
	git pull
	git submodule update --init --recursive

.PHONY: clean
clean:
	@echo Nothing to clean
