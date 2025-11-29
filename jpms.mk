ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk

# The following variables have default values which can be overriden
# JLINK_HOME        the Java runtime providing the jmod and jlink tools
# JLINK_JMODS       the directory where to find the Java jmods
JLINK_HOME ?= $(JAVA_HOME)
JLINK_JMODS ?= $(JLINK_HOME)/jmods

A2_JMODS=$(TARGET_NATIVE_OUTPUT)/jmods
# Note: replacing $${MODULES// /,} is bash specific
#JLINK_MODULES ?= $(shell . $(JLINK_HOME)/release && echo $${MODULES// /,})
JLINK_MODULES ?= $(subst $(space),$(comma),$(shell . $(JLINK_HOME)/release && echo $$MODULES))
JLINK_JAVA_VERSION = $(shell . $(JLINK_HOME)/release && echo $$JAVA_VERSION)
ifeq ("$(shell . $(JLINK_HOME)/release && echo $$JVM_VARIANT)","Openj9")
JLINK_JVM_VARIANT=openj9
else
ifneq ("$(shell . $(JLINK_HOME)/release && echo $$GRAALVM_VERSION)",)
JLINK_JVM_VARIANT=graalvm
else
JLINK_JVM_VARIANT=hotspot
endif
endif
JLINK_JAVA_RELEASE = $(firstword $(subst .,$(space),$(JLINK_JAVA_VERSION)))

JMODS_BASE=$(SDK_BUILD_BASE)/jmods

define a2_jmod_bare_module
	$(RM) -r $(JMODS_BASE)/$(1)/java
	$(RM) -r $(JMODS_BASE)/$(1)/classes
	mkdir -p $(JMODS_BASE)/$(1)/java
	mkdir -p $(JMODS_BASE)/$(1)/classes
	echo "module $(1) {}" > $(JMODS_BASE)/$(1)/java/module-info.java
	$(JLINK_HOME)/bin/javac --release 11 -d $(JMODS_BASE)/$(1)/classes \
	 $(JMODS_BASE)/$(1)/java/module-info.java
endef

# Minimal required OS libs for distribution
A2_OS_LIBS_CATEGORY=org.argeo.os.libs
JMOD_OS_LIBS=$(A2_OS_LIBS_CATEGORY)

ifeq ($(MSYS_VERSION),0)
A2_OS_LIBS=\
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/ld-linux-x86-64.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libc.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libstdc++.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libz.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libm.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libgcc_s.so.*

# TODO make it more robust
A2_OS_LIBS_VERSION = $(shell gcc -dumpversion).0.0
else
UCRT_BASE ?= /ucrt64
A2_OS_LIBS=\
$(UCRT_BASE)/bin/libgcc_s_seh-*.dll \
$(UCRT_BASE)/bin/libgomp-*.dll \
$(UCRT_BASE)/bin/libstdc++-*.dll \
$(UCRT_BASE)/bin/libwinpthread-*.dll
A2_OS_LIBS_VERSION = $(firstword $(subst -,$(space),$(shell pacman -Q mingw-w64-ucrt-x86_64-gcc-libs | awk '{print $$2}')))
#  pacman -Q mingw-w64-ucrt-x86_64-gcc-libs | awk '{print $2}'
endif

a2-prepare-os-libs: a2-prepare-output
	mkdir -p $(TARGET_NATIVE_OUTPUT)/$(A2_OS_LIBS_CATEGORY)
	cp $(A2_OS_LIBS) $(TARGET_NATIVE_OUTPUT)/$(A2_OS_LIBS_CATEGORY)
ifeq ($(MSYS_VERSION),0)
# No need to link on Linux
else
	ln -f -r -s $(TARGET_NATIVE_OUTPUT)/$(A2_OS_LIBS_CATEGORY)/$(SHLIB_PREFIX)*$(SHLIB_SUFFIX) \
	 $(TARGET_NATIVE_OUTPUT)	
endif

jmod-os-libs: a2-prepare-os-libs
	mkdir -p $(A2_JMODS)
	mkdir -p $(JMODS_BASE)/$(JMOD_OS_LIBS)/lib
ifeq ($(MSYS_VERSION),0)
# TODO copy only when standalone
else
	$(COPY) $(TARGET_NATIVE_OUTPUT)/$(A2_OS_LIBS_CATEGORY)/$(SHLIB_PREFIX)*$(SHLIB_SUFFIX) \
	 $(JMODS_BASE)/$(JMOD_OS_LIBS)/lib
endif	
	$(call a2_jmod_bare_module,$(JMOD_OS_LIBS))
		
	$(RM) $(A2_JMODS)/$(JMOD_OS_LIBS).jmod
	$(JLINK_HOME)/bin/jmod create \
	 --module-version $(A2_OS_LIBS_VERSION) \
	 --class-path $(JMODS_BASE)/$(JMOD_OS_LIBS)/classes \
	 --libs $(JMODS_BASE)/$(JMOD_OS_LIBS)/lib \
	 $(A2_JMODS)/$(JMOD_OS_LIBS).jmod

