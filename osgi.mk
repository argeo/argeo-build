ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk

# The following variables should be declared in the including Makefile:
# BUNDLES           the space-separated list of bundles to build
# A2_CATEGORY       the (single) a2 category the bundles will belong to

# The following environment variables can change the behaviour of the build
# SOURCE_BUNDLES    sources will be packaged separately in Eclipse-compatible source bundles

# The following variables have default values which can be overriden
# DEP_CATEGORIES    the a2 categories the compilation depends on
# JAVADOC_PACKAGES  the space-separated list of packages for which javadoc will be generated
# NATIVE_PACKAGES   the space-separated list of JNI packages (directories)
DEP_CATEGORIES ?=
JAVADOC_PACKAGES ?=
NATIVE_PACKAGES ?=

# We always use the latest version of the ECJ compiler
ECJ_JAR ?= $(firstword $(foreach base, $(A2_BASE), $(sort $(wildcard $(base)/org.argeo.tp.build/org.eclipse.jdt.core.compiler.batch.$(ECJ_MAJOR).*.jar))))
# Third-party libraries
LOGGER_JAR ?= $(firstword $(foreach base, $(A2_BASE), $(wildcard $(base)/log/syslogger/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar)))
BNDLIB_JAR ?= $(firstword $(foreach base, $(A2_BASE), $(wildcard $(base)/org.argeo.tp.build/biz.aQute.bndlib.$(BNDLIB_BRANCH).jar)))

# Internal variables
ARGEO_MAKE = $(JVM) -cp $(LOGGER_JAR):$(ECJ_JAR):$(BNDLIB_JAR) $(ARGEO_BUILD_BASE)src/org/argeo/build/Make.java
JAVADOC_SRCS = $(foreach bundle, $(BUNDLES), $(bundle)/src)
#ifneq ($(NO_MANIFEST_COPY),true)
MANIFESTS = $(foreach bundle, $(BUNDLES), $(bundle)/META-INF/MANIFEST.MF)
#endif
BUILD_BASE = $(SDK_BUILD_BASE)/$(shell basename $(SDK_SRC_BASE))
TARGET_BUNDLES =  $(abspath $(foreach bundle, $(BUNDLES),$(A2_OUTPUT)/$(shell dirname $(bundle))/$(A2_CATEGORY)/$(shell basename $(bundle)).$(major).$(minor).jar))
TODOS = $(foreach bundle, $(BUNDLES),$(BUILD_BASE)/$(bundle)/to-build) 
# Native
JNIDIRS=$(foreach package, $(NATIVE_PACKAGES), jni/$(package))

# Needed in order to be able to expand $$ variables
.SECONDEXPANSION:

osgi: $(BUILD_BASE)/built $(MANIFESTS)

# Actual build (compilation + bundle packaging)
$(BUILD_BASE)/built : BUNDLES_TO_BUILD = $(strip $(subst $(abspath $(BUILD_BASE))/,, $(subst to-build,, $?)))
$(BUILD_BASE)/built : $(TODOS)
	@echo "| A2 category  : $(A2_CATEGORY)"
	@echo "| Bundles      : $(BUNDLES_TO_BUILD)"
	@echo "| Dependencies : $(DEP_CATEGORIES)"
	@echo "| Compiler     : $(notdir $(ECJ_JAR))"
	@$(ARGEO_MAKE) \
	 all --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) \
	 --category $(A2_CATEGORY) --bundles $(BUNDLES_TO_BUILD)
	@touch $(BUILD_BASE)/built 

$(A2_OUTPUT)/%.$(major).$(minor).jar : $(BUILD_BASE)/$$(subst $(A2_CATEGORY)/,,$$*)/to-build
	$(ARGEO_MAKE) \
	 all --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) \
	 --category $(A2_CATEGORY) --bundles $(subst $(A2_CATEGORY)/,,$*)

$(BUILD_BASE)/%/to-build : $$(shell find % -type f -not -path 'bin/*' -not -path '*/MANIFEST.MF' | sed 's/ /\\ /g')
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@) 
	@touch $@

## DISABLED
# NO_MANIFEST_COPY  generated MANIFESTs won't be copied to the source tree

# Local manifests
%/META-INF/MANIFEST.MF : $(BUILD_BASE)/%/META-INF/MANIFEST.MF
#ifneq ($(NO_MANIFEST_COPY),true)
	@mkdir -p $*/META-INF
	@cp $< $@
#endif

clean-manifests :
	@rm -rf $(foreach bundle, $(BUNDLES), $(bundle)/META-INF/MANIFEST.MF);

osgi-all: osgi jni-all

osgi-clean: jni-clean
	rm -rf $(BUILD_BASE)

osgi-install: jni-install
	$(ARGEO_MAKE) \
	 install --category $(A2_CATEGORY) --bundles $(BUNDLES) \
	 --target $(A2_INSTALL_TARGET) \
	 --os $(TARGET_OS) --target-native $(A2_NATIVE_INSTALL_TARGET)

osgi-uninstall: jni-uninstall
	$(ARGEO_MAKE) \
	 uninstall --category $(A2_CATEGORY) --bundles $(BUNDLES) \
	 --target $(A2_INSTALL_TARGET) \
	 --os $(TARGET_OS) --target-native $(A2_NATIVE_INSTALL_TARGET)

jni-all: 
	$(foreach dir, $(JNIDIRS), $(MAKE) -C $(dir) all;)
	
jni-clean:
	$(foreach dir, $(JNIDIRS), $(MAKE) -C $(dir) clean;)

jni-install:
	$(foreach dir, $(JNIDIRS), $(MAKE) -C $(dir) install;)

jni-uninstall:
	$(foreach dir, $(JNIDIRS), $(MAKE) -C $(dir) uninstall;)

# Javadoc generation
javadoc: $(BUILD_BASE)/built
	$(JAVADOC) -noindex -quiet -Xmaxwarns 1 -d $(BUILD_BASE)/api --source-path $(subst $(space),$(pathsep),$(strip $(JAVADOC_SRCS))) -subpackages $(JAVADOC_PACKAGES)

.PHONY: osgi manifests javadoc osgi-all osgi-clean osgi-install osgi-uninstall jni-all jni-clean jni-install jni-uninstall
