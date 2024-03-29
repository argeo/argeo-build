# WARNING: this Makefile is for Argeo Build to build itself
# and is not meant to be included or used in regular builds
include sdk.mk

# Tells Make.java that we are our own Argeo Build
export ARGEO_BUILD_CONFIG := .

A2_CATEGORY = org.argeo.build

BUNDLES = \
org.argeo.build \

DEP_CATEGORIES = \
log/syslogger/org.argeo.tp \
org.argeo.tp.build \

all: osgi
# copy generated MANIFEST
	cp org.argeo.build/META-INF/MANIFEST.MF META-INF/MANIFEST.MF
	rm -rf org.argeo.build 

clean:
	rm -rf $(BUILD_BASE)

include osgi.mk