build-major=2
build-minor=3

# Required third party libraries
ECJ_MAJOR=3
BNDLIB_BRANCH=5.3
SYSLOGGER_BRANCH=$(build-major).$(build-minor)

# GNU defaults
prefix ?= /usr/local
datarootdir ?= $(prefix)/share
exec_prefix ?= $(prefix)
libdir ?= $(exec_prefix)/lib

A2_INSTALL_TARGET ?= $(DESTDIR)$(datarootdir)/a2
A2_NATIVE_INSTALL_TARGET ?= $(DESTDIR)$(libdir)/a2

# OS-speciific
KNOWN_ARCHS ?= x86_64 aarch64
TARGET_OS ?= linux
TARGET_ARCH ?= $(shell uname -m)

TARGET_OS_CATEGORY_PREFIX=lib/linux
TARGET_ARCH_CATEGORY_PREFIX=$(TARGET_OS_CATEGORY_PREFIX)/$(TARGET_ARCH)
PORTABLE_CATEGORIES=$(filter-out lib/%, $(CATEGORIES))
ARCH_CATEGORIES=$(filter $(TARGET_ARCH_CATEGORY_PREFIX)/%, $(CATEGORIES))
OS_CATEGORIES=$(filter-out $(foreach arch, $(KNOWN_ARCHS), $(TARGET_OS_CATEGORY_PREFIX)/$(arch)/%), $(filter $(TARGET_OS_CATEGORY_PREFIX)/%, $(CATEGORIES)))