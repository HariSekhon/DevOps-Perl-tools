#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

.PHONY: make
make:
	[ -x /usr/bin/apt-get ] && make apt-packages || :
	[ -x /usr/bin/yum ]     && make yum-packages || :

	git submodule init
	git submodule update

	cd lib && make

	# don't track and commit your personal name, company name etc additions to scrub_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged scrub_custom.conf

	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	yes | sudo cpan \
		JSON \
		LWP::Simple \
		LWP::UserAgent \
		Term::ReadKey \
		Text::Unidecode \
		Time::HiRes \
		XML::LibXML \
		XML::Validate
#		IO::Socket::SSL \
#		Net::LDAP  \
#		Net::LDAP::Filter \
#		Net::LDAPI \
#		Net::LDAPS \

.PHONY: apt-packages
apt-packages:
	apt-get install -y gcc || :
	# needed to fetch the library submodule at end of build
	apt-get install -y git || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	#apt-get install -y libssl-dev || :
	# needed to build XML::LibXML
	apt-get install -y libxml2-dev || :

.PHONY: yum-packages
yum-packages:
	yum install -y gcc || :
	# needed to fetch the library submodule and CPAN modules
	yum install -y perl-CPAN git || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	#yum install -y openssl-devel || :
	# needed to build XML::LibXML
	yum install -y libxml2-devel || :

.PHONY: test
test:
	cd lib && make test
	# TODO: add my functional tests back in here	

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH"

.PHONY: update
update:
	git pull
	git submodule update
	make
	make test
