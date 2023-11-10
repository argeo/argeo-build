build-major=2
build-minor=1

# Required third party libraries
ECJ_MAJOR=3
BNDLIB_BRANCH=5.3
SYSLOGGER_BRANCH=$(build-major).$(build-minor)

# GNU defaults
prefix ?= /usr/local
datarootdir ?= $(prefix)/share

A2_INSTALL_TARGET ?= $(DESTDIR)$(datarootdir)/a2