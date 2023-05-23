build-major=2
build-minor=3

# Required third party libraries
ECJ_BRANCH=3.32
BNDLIB_BRANCH=5.3
SYSLOGGER_BRANCH=$(build-major).$(build-minor)

# GNU defaults
prefix ?= /usr/local
datarootdir ?= $(prefix)/share

A2_INSTALL_TARGET ?= $(datarootdir)/a2