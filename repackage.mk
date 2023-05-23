ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk
#
# Common repackage routines to be included in Makefiles
#
# The following variables are found in the sdk.mk file which is generated by the configure script:
# SDK_SRC_BASE		the base of the source code, typically the root of the cloned git repository
# SDK_BUILD_BASE	the base of the output
# JAVA_HOME			the base of the JDK used to build
A2_OUTPUT = $(SDK_BUILD_BASE)/a2
JVM ?= $(JAVA_HOME)/bin/java

# The following variables should be declared in the including Makefile:
# CATEGORIES		the space-separated list of categories to repackage

# The following variables have default values which can be overriden
# A2_BASE			the space-separated directories where already built a2 categories can be found
A2_BASE ?=/usr/share/a2 /usr/local/share/a2 $(A2_OUTPUT)

# Third-party libraries
LOGGER_JAR ?= $(lastword $(foreach base, $(A2_BASE), $(wildcard $(base)/log/syslogger/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar)))
BNDLIB_JAR ?= $(lastword $(foreach base, $(A2_BASE), $(wildcard $(base)/org.argeo.tp.build/biz.aQute.bndlib.$(BNDLIB_BRANCH).jar)))

# Internal variables
ARGEO_REPACKAGE = $(JVM) -cp $(LOGGER_JAR):$(BNDLIB_JAR) $(ARGEO_BUILD_BASE)src/org/argeo/build/Repackage.java
TODOS_REPACKAGE = $(foreach category, $(CATEGORIES),$(BUILD_BASE)/$(category)/to-repackage) 
BUILD_BASE = $(SDK_BUILD_BASE)/$(shell basename $(SDK_SRC_BASE))
REPACKAGED_CATEGORIES = $(foreach category, $(CATEGORIES),$(A2_OUTPUT)/$(category))

all: $(BUILD_BASE)/repackaged 

install:
	@$(foreach category, $(CATEGORIES), mkdir -p $(A2_INSTALL_TARGET)/$(category);  cp $(A2_OUTPUT)/$(category)/*.jar $(A2_INSTALL_TARGET)/$(category);)

uninstall:
	@$(foreach category, $(CATEGORIES), rm -rf $(A2_INSTALL_TARGET)/$(category);)
	find $(A2_INSTALL_TARGET) -empty -type d -delete

.SECONDEXPANSION:
# We use .SECONDEXPANSION and CATEGORIES_TO_REPACKAGE instead of directly CATEGORIES
# so that we don't repackage a category if it hasn't changed
$(BUILD_BASE)/repackaged : CATEGORIES_TO_REPACKAGE = $(subst $(abspath $(BUILD_BASE))/,, $(subst to-repackage,, $?))
$(BUILD_BASE)/repackaged : $(TODOS_REPACKAGE)
	$(ARGEO_REPACKAGE) $(A2_OUTPUT) $(CATEGORIES_TO_REPACKAGE)
	touch $(BUILD_BASE)/repackaged

$(BUILD_BASE)/%/to-repackage : $$(shell find % -type f )
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@) 
	@touch $@

clean:
	$(foreach category, $(CATEGORIES), rm -rf $(BUILD_BASE)/$(category))
	rm -f $(BUILD_BASE)/repackaged
