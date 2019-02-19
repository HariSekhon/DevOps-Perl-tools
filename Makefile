#  vim:ts=4:sts=4:sw=4:noet
#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/devops-perl-tools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# ===================
# bootstrap commands:

# Alpine:
#
#   apk add --no-cache git $(MAKE) && git clone https://github.com/harisekhon/devops-perl-tools && cd tools && $(MAKE)

# Debian / Ubuntu:
#
#   apt-get update && apt-get install -y $(MAKE) git && git clone https://github.com/harisekhon/devops-perl-tools && cd tools && $(MAKE)

# RHEL / CentOS:
#
#   yum install -y $(MAKE) git && git clone https://github.com/harisekhon/devops-perl-tools && cd tools && $(MAKE)

# ===================

ifneq ("$(wildcard bash-tools/Makefile.in)", "")
	include bash-tools/Makefile.in
endif

.PHONY: build
build:
	@echo ================
	@echo Perl Tools Build
	@echo ================

	$(MAKE) init
	if [ -z "$(CPANM)" ]; then make; exit $?; fi
	$(MAKE) system-packages
	$(MAKE) perl

	# don't track and commit your personal name, company name etc additions to anonymize_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged anonymize_custom.conf
	git update-index --assume-unchanged solr/solr-env.sh

	@echo
	@echo "BUILD SUCCESSFUL (tools)"

.PHONY: init
init:
	git submodule update --init --recursive

.PHONY: perl
perl: perl-libs
	# workaround for broken pod coverage tests
	#yes | $(SUDO) cpan --force XML::Validate

	@bash-tools/perl_cpanm_install_if_absent.sh setup/cpan-requirements.txt setup/cpan-requirements-packaged.txt

.PHONY: perl-libs
perl-libs:
	cd lib && $(MAKE)

.PHONY: lib-test
lib-test:
	cd lib && $(MAKE) test
	rm -fr lib/cover_db || :

.PHONY: test
test: lib-test
	tests/all.sh

.PHONY: basic-test
basic-test: lib-test
	. tests/excluded.sh; bash-tools/all.sh
	tests/help.sh

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH"

.PHONY: clean
clean:
	cd lib && $(MAKE) clean

.PHONY: deep-clean
deep-clean: clean
	cd lib && $(MAKE) deep-clean
