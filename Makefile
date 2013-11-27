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
	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	sudo cpan LWP::Simple \
		 LWP::UserAgent \
		 Text::Unidecode \
		 Time::HiRes \
		 XML::Validate

update:
	git pull
	make install
