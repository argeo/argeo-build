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
	@$(foreach category, $(PORTABLE_CATEGORIES), $(INSTALL) $(A2_INSTALL_TARGET)/$(category) $(wildcard $(A2_OUTPUT)/$(category)/*.jar);$(LF))
	@echo Installed portable jars \'$(PORTABLE_CATEGORIES)\' to $(A2_INSTALL_TARGET)
	@$(foreach category, $(OS_CATEGORIES), $(INSTALL) $(A2_INSTALL_TARGET)/$(category:$(TARGET_OS_CATEGORY_PREFIX)/%=%) $(wildcard $(A2_OUTPUT)/$(category)/*.jar);$(LF))
	@echo Installed OS-dependent jars \'$(OS_CATEGORIES)\' to $(A2_INSTALL_TARGET)
	@$(foreach category, $(ARCH_CATEGORIES), $(INSTALL) $(A2_NATIVE_INSTALL_TARGET)/$(category:$(TARGET_ARCH_CATEGORY_PREFIX)/%=%) $(wildcard $(A2_OUTPUT)/$(category)/*.jar);$(LF))
	@echo Installed arch-dependent jars \'$(ARCH_CATEGORIES)\' to $(A2_NATIVE_INSTALL_TARGET)
	@$(foreach category, $(ARCH_CATEGORIES), $(INSTALL) $(A2_NATIVE_INSTALL_TARGET) $(wildcard $(A2_OUTPUT)/$(category)/*.so);$(LF))
	@echo Installed arch binaries \'$(ARCH_CATEGORIES)\' to $(A2_NATIVE_INSTALL_TARGET)

uninstall:
	$(foreach category, $(PORTABLE_CATEGORIES), $(RMDIR) $(A2_INSTALL_TARGET)/$(category);$(LF))
	@echo Uninstalled portable jars \'$(PORTABLE_CATEGORIES)\' to $(A2_INSTALL_TARGET)
	$(foreach category, $(OS_CATEGORIES), $(RMDIR) $(A2_INSTALL_TARGET)/$(category:$(TARGET_OS_CATEGORY_PREFIX)/%=%);$(LF))
	@echo Uninstalled OS-dependent jars \'$(OS_CATEGORIES)\' to $(A2_INSTALL_TARGET)
	$(foreach category, $(ARCH_CATEGORIES), $(RMDIR) $(A2_NATIVE_INSTALL_TARGET)/$(category:$(TARGET_ARCH_CATEGORY_PREFIX)/%=%);$(LF))
	@echo Uninstalled arch-dependent jars \'$(ARCH_CATEGORIES)\' to $(A2_NATIVE_INSTALL_TARGET)
	$(foreach category, $(ARCH_CATEGORIES), \
	 $(foreach libfile, $(wildcard $(A2_OUTPUT)/$(category)/*.so), $(RMDIR) $(A2_NATIVE_INSTALL_TARGET)/$(notdir $(libfile));$(LF)) \
	)
	@echo Uninstalled arch binaries \'$(ARCH_CATEGORIES)\' to $(A2_NATIVE_INSTALL_TARGET)
	@find $(A2_INSTALL_TARGET) -empty -type d -delete
	@rmdir --ignore-fail-on-non-empty $(A2_INSTALL_TARGET)
	@find $(A2_NATIVE_INSTALL_TARGET) -empty -type d -delete
	@rmdir --ignore-fail-on-non-empty $(A2_NATIVE_INSTALL_TARGET)
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
