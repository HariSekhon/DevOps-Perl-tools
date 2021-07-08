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

# setup/bootstrap.sh
#
# OR
#
# Alpine:
#
#   apk add --no-cache git make && git clone https://github.com/harisekhon/devops-perl-tools && cd tools && make
#
# Debian / Ubuntu:
#
#   apt-get update && apt-get install -y make git && git clone https://github.com/harisekhon/devops-perl-tools && cd tools && make
#
# RHEL / CentOS:
#
#   yum install -y make git && git clone https://github.com/harisekhon/devops-perl-tools && cd tools && make

# ===================

ifneq ("$(wildcard bash-tools/Makefile.in)", "")
	include bash-tools/Makefile.in
endif

REPO := HariSekhon/DevOps-Perl-tools

CODE_FILES := $(shell find . -type f -name '*.pl' -o -type f -name '*.pm' -o -type f -name '*.sh' | grep -Eve /lib/ -e /bash-tools/ -e /fatpacks/)

.PHONY: build
build: init
	@echo ================
	@echo Perl Tools Build
	@echo ================
	@$(MAKE) git-summary
	@echo

	@# doesn't exit Make anyway, just doubles build time, and don't wanna use oneshell
	@#if [ -z "$(CPANM)" ]; then make; exit $$?; fi
	$(MAKE) system-packages-perl
	$(MAKE) perl

	# don't track and commit your personal name, company name etc additions to anonymize_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged anonymize_custom.conf
	git update-index --assume-unchanged solr/solr-env.sh

	@echo
	@echo "BUILD SUCCESSFUL (tools)"

.PHONY: init
init:
	pwd
	git submodule
	git submodule update --init --recursive

.PHONY: perl
perl: perl-libs cpan
	@# workaround for broken pod coverage tests
	@#yes | $(SUDO) cpan --force XML::Validate
	@#bash-tools/perl_cpanm_install_if_absent.sh setup/cpan-requirements.txt setup/cpan-requirements-packaged.txt
	@:

.PHONY: perl-libs
perl-libs:
	cd lib && $(MAKE)

.PHONY: fatpacks-local
fatpacks-local:
	cp -a sql-keywords templates "$(FATPACKS_DIR)/"

.PHONY: lib-test
lib-test:
	cd lib && $(MAKE) test
	rm -fr lib/cover_db || :

.PHONY: test
test: lib-test
	tests/all.sh

.PHONY: basic-test
basic-test: lib-test
	. tests/excluded.sh; bash-tools/check_all.sh
	tests/help.sh

.PHONY: install
install: build
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH"

.PHONY: clean
clean:
	cd lib && $(MAKE) clean

.PHONY: deep-clean
deep-clean: clean
	cd lib && $(MAKE) deep-clean

.PHONY: dockerhub-trigger
dockerhub-trigger:
	# Tools
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/1ce5ac1d-4ce6-4051-8246-2e05e042dfd7/trigger/6b4c6eeb-ed48-4e01-954f-ec2e0692ca35/call/
	# Alpine Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/df816f2a-9407-4f1b-8b51-39615d784e65/trigger/8d9cb826-48df-439c-8c20-1975713064fc/call/
	# Debian Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/439eff84-50c7-464a-a49e-0ac0bf1a9a43/trigger/0cfb3fe7-2028-494b-a43b-068435e6a2b3/call/
	# CentOS Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/efba1846-5a9e-470a-92f8-69edc1232ba0/trigger/316d1158-7ffb-49a4-a7bd-8e5456ba2d15/call/
	# Ubuntu Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/8b3dc094-d4ca-4c92-861e-1e842b5fac42/trigger/abd4dbf0-14bc-454f-9cde-081ec014bc48/call/
