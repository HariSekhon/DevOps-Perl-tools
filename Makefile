#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

.PHONY: install
install:
	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }

	# don't track and commit your personal name, company name etc additions to scrub_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged scrub_custom.conf

	[ -x /usr/bin/apt-get ] && make apt-packages || :
	[ -x /usr/bin/yum ]     && make yum-packages || :

	yes | sudo cpan \
		 JSON \
		 LWP::Simple \
		 LWP::UserAgent \
		 Term::ReadKey \
		 Text::Unidecode \
		 Time::HiRes \
		 XML::Validate
	git submodule init
	git submodule update

.PHONY: apt-packages
apt-packages:
	apt-get install -y gcc || :
	# needed to fetch the library submodule at end of build
	apt-get install -y git || :
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN

.PHONY: yum-packages
yum-packages:
	yum install -y gcc || :
	# needed to fetch the library submodule at end of build
	yum install -y git || :
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN

.PHONY: update
update:
	git pull
	git submodule update
	make install
