build-major=2
build-minor=3

# Required third party libraries
ECJ_MAJOR=3
BNDLIB_BRANCH=5.3
SYSLOGGER_BRANCH=$(build-major).$(build-minor)

# GNU defaults
prefix ?= /usr/local
datarootdir ?= $(prefix)/share
libdir ?= $(exec_prefix)/lib

A2_INSTALL_TARGET ?= $(DESTDIR)$(datarootdir)/a2
A2_NATIVE_INSTALL_TARGET ?= $(DESTDIR)$(libdir)/a2

# OS-speciific
OS_CATEGORY_PREFIX=lib/linux
ARCH_CATEGORY_PREFIX=$(OS_CATEGORY_PREFIX)/$(shell uname -m)

PORTABLE_CATEGORIES=$(filter-out $(OS_CATEGORY_PREFIX)/%, $(CATEGORIES))
ARCH_CATEGORIES=$(filter $(ARCH_CATEGORY_PREFIX)/%, $(CATEGORIES))
OS_CATEGORIES=$(filter-out $(ARCH_CATEGORY_PREFIX)/%, $(filter $(OS_CATEGORY_PREFIX)/%, $(CATEGORIES)))