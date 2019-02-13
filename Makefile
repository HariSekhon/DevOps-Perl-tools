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

export PATH := $(PATH):/usr/local/bin

CPANM = cpanm

ifdef PERLBREW_PERL
	SUDO_PERL =
else
	SUDO_PERL = sudo
endif

# must come after to reset SUDO_PERL to blank if root
# EUID /  UID not exported in Make
# USER not populated in Docker
ifeq '$(shell id -u)' '0'
	SUDO =
	SUDO_PERL =
else
	SUDO = sudo
endif

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

.PHONY: build
build:
	@echo ================
	@echo Perl Tools Build
	@echo ================

	$(MAKE) common
	$(MAKE) perl

	# don't track and commit your personal name, company name etc additions to anonymize_custom.conf back to Git since they are personal to you
	git update-index --assume-unchanged anonymize_custom.conf
	git update-index --assume-unchanged solr/solr-env.sh

	@echo
	@echo "BUILD SUCCESSFUL (tools)"

.PHONY: common
common: system-packages submodules
	:

.PHONY: submodules
submodules:
	git submodule init
	git submodule update --recursive

.PHONY: system-packages
system-packages:
	if [ -x /sbin/apk ];        then $(MAKE) apk-packages; fi
	if [ -x /usr/bin/apt-get ]; then $(MAKE) apt-packages; fi
	if [ -x /usr/bin/yum ];     then $(MAKE) yum-packages; fi
	if [ -x /usr/local/bin/brew -a `uname` = Darwin ]; then $(MAKE) homebrew-packages; fi

.PHONY: perl
perl: perl-libs
	#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	# Module::CPANfile::Result and Module::Install::Admin are needed for Hijk which is auto-pulled by Search::Elasticsearch but doesn't auto-pull Module::CPANfile::Result

	# workaround for broken pod coverage tests
	#yes | $(SUDO) cpan --force XML::Validate

	# auto-configure cpan for Perl 5.8 which otherwise gets stuck prompting for a region for downloads
	# this doesn't work it's misaligned with the prompts, should use expect instead if I were going to do this
	#(echo y;echo o conf prerequisites_policy follow;echo o conf commit) | cpan
	which cpanm || { yes "" | $(SUDO_PERL) cpan App::cpanminus; }
	@echo
	# Workaround for Mac OS X not finding the OpenSSL libraries when building
	if [ -d /usr/local/opt/openssl/include -a \
	     -d /usr/local/opt/openssl/lib     -a \
	     `uname` = Darwin ]; then \
	     yes "" | $(SUDO_PERL) OPENSSL_INCLUDE=/usr/local/opt/openssl/include OPENSSL_LIB=/usr/local/opt/openssl/lib $(CPANM) --notest Crypt::SSLeay; \
	fi
	@echo
	@echo "Installing CPAN Modules"
	#yes "" | $(SUDO_PERL) $(CPANM) --notest `sed 's/#.*//; /^[[:space:]]*$$/d;' setup/cpan-requirements.txt`
	@echo
	@echo "Installing any CPAN Modules missed by system packages"
	for cpan_module in `sed 's/#.*//; /^[[:space:]]*$$/d' setup/cpan-requirements-packaged.txt`; do \
		perl -e "use $$cpan_module;" || $(SUDO_PERL) $(CPANM) --notest "$$cpan_module" || exit 1; \
	done

.PHONY: perl-libs
perl-libs:
	cd lib && $(MAKE)

.PHONY: quick
quick:
	QUICK=1 $(MAKE)

.PHONY: apk-packages
apk-packages:
	$(SUDO) apk update
	$(SUDO) apk add `sed 's/#.*//; /^[[:space:]]*$$/d' setup/apk-packages.txt setup/apk-packages-dev.txt`

.PHONY: apk-packages-remove
apk-packages-remove:
	cd lib && $(MAKE) apk-packages-remove
	$(SUDO) apk del `sed 's/#.*//; /^[[:space:]]*$$/d' < setup/apk-packages-dev.txt` || :
	$(SUDO) rm -fr /var/cache/apk/*

.PHONY: apt-packages
apt-packages:
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y `sed 's/#.*//; /^[[:space:]]*$$/d' setup/deb-packages.txt setup/deb-packages-dev.txt`
	$(SUDO) apt-get install -y `sed 's/#.*//; /^[[:space:]]*$$/d' setup/deb-packages-cpan.txt` || :

.PHONY: apt-packages-remove
apt-packages-remove:
	cd lib && $(MAKE) apt-packages-remove
	$(SUDO) apt-get purge -y `sed 's/#.*//; /^[[:space:]]*$$/d' < setup/deb-packages-dev.txt`

.PHONY: yum-packages
yum-packages:
	# to fetch and untar ZooKeeper, plus wget epel rpm
	rpm -q wget || yum install -y wget
	
	# epel-release is in the list of rpms to install via yum in setup/rpm-packages.txt but this is a more backwards compatible method of installing that will work on older versions of RHEL / CentOS as well so is left here for compatibility purposes
	#
	# python-pip requires EPEL, so try to get the correct EPEL rpm
	# this doesn't work for some reason CentOS 5 gives 'error: skipping https://dl.fedoraproject.org/pub/epel/epel-release-latest-5.noarch.rpm - transfer failed - Unknown or unexpected error'
	# must instead do wget
	rpm -q epel-release      || yum install -y epel-release || { wget -t 5 --retry-connrefused -O /tmp/epel.rpm "https://dl.fedoraproject.org/pub/epel/epel-release-latest-`grep -o '[[:digit:]]' /etc/*release | head -n1`.noarch.rpm" && $(SUDO) rpm -ivh /tmp/epel.rpm && rm -f /tmp/epel.rpm; }

	for x in `sed 's/#.*//; /^[[:space:]]*$$/d' setup/rpm-packages.txt setup/rpm-packages-dev.txt`; do rpm -q $$x || $(SUDO) yum install -y $$x; done

.PHONY: yum-packages-remove
yum-packages-remove:
	cd lib && $(MAKE) yum-packages-remove
	for x in `sed 's/#.*//; /^[[:space:]]*$$/d' < setup/rpm-packages-dev.txt`; do rpm -q $$x && $(SUDO) yum remove -y $$x; done

.PHONY: homebrew-packages
homebrew-packages:
	# Sudo is not required as running Homebrew as root is extremely dangerous and no longer supported as Homebrew does not drop privileges on installation you would be giving all build scripts full access to your system
	# Fails if any of the packages are already installed, ignore and continue - if it's a problem the latest build steps will fail with missing headers
	brew install `sed 's/#.*//; /^[[:space:]]*$$/d' setup/brew-packages.txt` || :

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

.PHONY: update
update: update2 build
	:
	@#$(MAKE) test

.PHONY: update2
update2: update-no-recompile
	:

.PHONY: update-no-recompile
update-no-recompile:
	git pull
	git submodule update --init --recursive

.PHONY: update-submodules
update-submodules:
	git submodule update --init --remote
.PHONY: updatem
updatem: update-submodules
	:

.PHONY: clean
clean:
	cd lib && $(MAKE) clean

.PHONY: deep-clean
deep-clean: clean
	cd lib && $(MAKE) deep-clean

.PHONY: docker-run
docker-run:
	docker run -ti --rm harisekhon/tools ${ARGS}

.PHONY: run
run:
	$(MAKE) docker-run

.PHONY: docker-mount
docker-mount:
	docker run -ti --rm -v $$PWD:/tools harisekhon/tools bash -c "cd /tools; exec bash"

.PHONY: mount
mount: docker-mount
	:

.PHONY: push
push:
	git push
