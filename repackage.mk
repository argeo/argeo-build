ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk

# The following variables should be declared in the including Makefile:
# CATEGORIES        the space-separated list of categories to repackage

A2_BASE ?=/usr/share/a2 /usr/local/share/a2 $(A2_OUTPUT)

# Third-party libraries
LOGGER_JAR ?= $(firstword $(foreach base, $(A2_BASE), $(wildcard $(base)/log/syslogger/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar)))
BNDLIB_JAR ?= $(firstword $(foreach base, $(A2_BASE), $(wildcard $(base)/org.argeo.tp.build/biz.aQute.bndlib.$(BNDLIB_BRANCH).jar)))

# Internal variables
ARGEO_REPACKAGE = $(JVM) -cp $(LOGGER_JAR):$(BNDLIB_JAR) $(ARGEO_BUILD_BASE)src/org/argeo/build/Repackage.java
TODOS_REPACKAGE = $(foreach category, $(CATEGORIES),$(BUILD_BASE)/$(category)/to-repackage) 
BUILD_BASE = $(SDK_BUILD_BASE)/$(shell basename $(SDK_SRC_BASE))
REPACKAGED_CATEGORIES = $(foreach category, $(CATEGORIES),$(A2_OUTPUT)/$(category))

all: $(BUILD_BASE)/repackaged 

install:
	@$(foreach category, $(PORTABLE_CATEGORIES), install -D $(wildcard $(A2_OUTPUT)/$(category)/*.jar) $(A2_INSTALL_TARGET)/$(category))
	@echo Installed portable jars '$(PORTABLE_CATEGORIES)' to $(A2_INSTALL_TARGET)
	@$(foreach category, $(OS_CATEGORIES), install -D $(wildcard $(A2_OUTPUT)/$(category)/*.jar) $(A2_INSTALL_TARGET)/$(category))
	@echo Installed OS-dependent jars '$(OS_CATEGORIES)' to $(A2_INSTALL_TARGET)
	@$(foreach category, $(ARCH_CATEGORIES), install -D $(wildcard $(A2_OUTPUT)/$(category)/*.jar) $(subst, $(TARGET_ARCH_CATEGORY_PREFIX)/,, $(category)))
	@echo Installed arch-dependent jars '$(ARCH_CATEGORIES)' to $(A2_NATIVE_INSTALL_TARGET)
	@$(foreach category, $(ARCH_CATEGORIES), install -D $(wildcard $(A2_OUTPUT)/$(category)/*.so) $(A2_NATIVE_INSTALL_TARGET);)
	@echo Installed arch binaries '$(ARCH_CATEGORIES)' to $(A2_NATIVE_INSTALL_TARGET)

uninstall:
	@$(foreach category, $(CATEGORIES), rm -rf $(A2_INSTALL_TARGET)/$(category);)
	@find $(A2_INSTALL_TARGET) -empty -type d -delete
	@echo Uninstalled $(CATEGORIES) from $(A2_INSTALL_TARGET)

.SECONDEXPANSION:
# We use .SECONDEXPANSION and CATEGORIES_TO_REPACKAGE instead of directly CATEGORIES
# so that we don't repackage a category if it hasn't changed
$(BUILD_BASE)/repackaged : CATEGORIES_TO_REPACKAGE = $(subst $(abspath $(BUILD_BASE))/,, $(subst to-repackage,, $?))
$(BUILD_BASE)/repackaged : $(TODOS_REPACKAGE)
	@$(ARGEO_REPACKAGE) $(A2_OUTPUT) $(CATEGORIES_TO_REPACKAGE)
	@touch $(BUILD_BASE)/repackaged

$(BUILD_BASE)/%/to-repackage : $$(shell find % -type f )
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@) 
	@touch $@

clean:
	@$(foreach category, $(CATEGORIES), rm -rf $(BUILD_BASE)/$(category))
	@rm -f $(BUILD_BASE)/repackaged
