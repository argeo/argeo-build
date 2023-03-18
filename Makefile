# WARNING: this Makefile is for Argeo Build to build itself
# and is not meant to be included or used in regular builds
include sdk.mk

# Tells Make.java that we are our own Argeo Build
export ARGEO_BUILD_CONFIG := .

A2_CATEGORY = org.argeo.build

BUNDLES = \
org.argeo.build \

DEP_CATEGORIES = \
org.argeo.tp \
org.argeo.tp.sdk \

all: osgi
# copy generated MANIFEST
	cp org.argeo.build/META-INF/MANIFEST.MF META-INF/MANIFEST.MF
	rm -rf org.argeo.build 

include osgi.mk