#
#   Author: Hari Sekhon
#   Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#  $LastChangedBy$
#  $LastChangedDate$
#  $Revision$
#  $URL$
#  $Id$
#
#  vim:ts=4:sw=4

.PHONY: make
make install:
	@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	cpan LWP::UserAgent
	git submodule init
	git sudmodule update
