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
	git submodule init
	git submodule update
	# don't track and commit your personal name, company name etc additions to scrub_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged scrub_custom.conf
	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	sudo cpan LWP::Simple \
		 LWP::UserAgent \
		 Term::ReadKey \
		 Text::Unidecode \
		 Time::HiRes \
		 XML::Validate

.PHONY: update
update:
	git pull
	git submodule update
	make install
