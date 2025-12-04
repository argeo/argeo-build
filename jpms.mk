ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk

# The following variables have default values which can be overriden
# JLINK_HOME        the Java runtime providing the jmod and jlink tools
# JLINK_JMODS       the directory where to find the Java jmods
# JLINK_RT_MODULES  minimal set of modules when creating a runtime
JLINK_HOME ?= $(JAVA_HOME)
JLINK_JMODS ?= $(JLINK_HOME)/jmods
JLINK_RT_MODULES ?= java.base

# Note: replacing $${MODULES// /,} is bash specific
JLINK_JAVA_MODULES ?= $(subst $(space),$(comma),$(shell . "$(JLINK_HOME)/release" && echo $$MODULES))
JLINK_JAVA_VERSION = $(shell . "$(JLINK_HOME)/release" && echo $$JAVA_VERSION)

# JVM variant
ifeq ("$(shell . "$(JLINK_HOME)/release" && echo $$IMPLEMENTOR)","Eclipse OpenJ9") # Linux
JLINK_JVM_VARIANT=openj9
endif
ifeq ("$(shell . "$(JLINK_HOME)/release" && echo $$JVM_VARIANT)","Openj9") # Windows, MacOS
JLINK_JVM_VARIANT=openj9
endif
ifneq ("$(shell . "$(JLINK_HOME)/release" && echo $$GRAALVM_VERSION)","")
JLINK_JVM_VARIANT=graalvm
endif
ifeq ("$(JLINK_JVM_VARIANT)","") # default
JLINK_JVM_VARIANT=hotspot
endif

JLINK_JAVA_RELEASE = $(firstword $(subst .,$(space),$(JLINK_JAVA_VERSION)))

#
# JMOD CREATION
#
A2_JMODS=$(A2_OUTPUT)/jmods
A2_JMODS_NATIVE=$(TARGET_NATIVE_OUTPUT)/jmods

JLINK_A2_JMODS=$(A2_JMODS)/$(JLINK_JAVA_RELEASE)
JLINK_A2_JMODS_NATIVE=$(A2_JMODS_NATIVE)/$(JLINK_JAVA_RELEASE)
JMODS_BASE=$(SDK_BUILD_BASE)/jmods

JLINK_SUFFIX = $(JLINK_JAVA_RELEASE)-$(JLINK_JVM_VARIANT)-$(TARGET_NATIVE_CATEGORY_PREFIX)

define a2_jmod_bare_module # (moduleName)
	echo "module $(1) {}" > $(JMODS_BASE)/$(1)/java/module-info.java
	"$(JLINK_HOME)/bin/javac" --release $(JLINK_JAVA_RELEASE) -d $(JMODS_BASE)/$(1)/classes \
	 $(JMODS_BASE)/$(1)/java/module-info.java
endef

define a2_jmod_prepare_output # (moduleName)
	@$(RM) -r $(JMODS_BASE)/$(1)
	@mkdir -p $(JMODS_BASE)/$(1)/java
	@mkdir -p $(JMODS_BASE)/$(1)/classes
	@mkdir -p $(JMODS_BASE)/$(1)/config
	@mkdir -p $(JMODS_BASE)/$(1)/legal
	@mkdir -p $(JMODS_BASE)/$(1)/man
	@mkdir -p $(JMODS_BASE)/$(1)/bin
	@mkdir -p $(JMODS_BASE)/$(1)/lib
	@mkdir -p $(JMODS_BASE)/$(1)/include
endef

define a2_jmod_create # (bundle)
	$(RM) $(JLINK_A2_JMODS)/$(1).jmod
	mkdir -p $(JLINK_A2_JMODS)
	
	"$(JLINK_HOME)/bin/jmod" create \
	 --module-version $(A2_LAYER_VERSION) \
	 --class-path "$(A2_OUTPUT)/$(A2_CATEGORY)/$(1).$(major).$(minor).jar$(file_path_sep)$(JMODS_BASE)/$(1)/classes" \
	 --config "$(JMODS_BASE)/$(1)/config" \
	 --man-pages "$(JMODS_BASE)/$(1)/man" \
	 --legal-notices "$(JMODS_BASE)/$(1)/legal" \
	 "$(JLINK_A2_JMODS)/$(1).jmod"
endef

define a2_jmod_create_native # (moduleName,moduleVersion)
	$(RM) $(JLINK_A2_JMODS_NATIVE)/$(TARGET_NATIVE_CATEGORY_PREFIX)-$(1).jmod
	mkdir -p $(JLINK_A2_JMODS_NATIVE)
	
	"$(JLINK_HOME)/bin/jmod" create \
	 --module-version $(2) \
	 --class-path "$(JMODS_BASE)/$(1)/classes" \
	 --target-platform "$(JMOD_TARGET_PLATFORM)" \
	 --config "$(JMODS_BASE)/$(1)/config" \
	 --man-pages "$(JMODS_BASE)/$(1)/man" \
	 --legal-notices "$(JMODS_BASE)/$(1)/legal" \
	 --libs "$(JMODS_BASE)/$(1)/lib" \
	 --cmds "$(JMODS_BASE)/$(1)/bin" \
	 --header-files "$(JMODS_BASE)/$(1)/include" \
	 "$(JLINK_A2_JMODS_NATIVE)/$(TARGET_NATIVE_CATEGORY_PREFIX)-$(1).jmod"
	
	# list content
	"$(JLINK_HOME)/bin/jmod" list "$(JLINK_A2_JMODS_NATIVE)/$(TARGET_NATIVE_CATEGORY_PREFIX)-$(1).jmod"
endef

#
# JDK/JRE CREATION
#
define a2_jlink_create_jdk # (jdkName)	
	$(RM) -r $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)
	"$(JLINK_HOME)/bin/jlink" \
	 --module-path "$(JLINK_JMODS)$(file_path_sep)$(JLINK_A2_JMODS)$(file_path_sep)$(JLINK_A2_JMODS_NATIVE)" \
	 --add-modules $(JLINK_RT_MODULES),$(JLINK_JAVA_MODULES),$(subst $(space),$(comma),$(MODULES) $(JLINK_NATIVE_JMODS)) \
	 --output "$(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)"
	
	cp $(JLINK_HOME)/lib/src.zip $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/lib
	
	mkdir -p $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src
	$(foreach module,$(MODULES),cp -r $(module)/src $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src/$(module))
	"$(JLINK_HOME)/bin/jar" -u -f $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/lib/src.zip \
	 -C $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src $(MODULES)
	$(RM) -r $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src
	
	mkdir -p $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/jmods
	$(foreach module,$(MODULES),\
	 $(COPY) $(JLINK_A2_JMODS)/*$(module).jmod $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/jmods; \
	)
	$(foreach module,$(JLINK_NATIVE_JMODS),\
	 $(COPY) $(JLINK_A2_JMODS_NATIVE)/*$(module).jmod $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/jmods; \
	)

	mkdir -p $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/lib/a2/$(A2_CATEGORY)
	$(COPY) -v $(A2_OUTPUT)/$(A2_CATEGORY)/*.jar $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/lib/a2/$(A2_CATEGORY)
endef

define a2_jlink_create_rt # (rtName)	
	$(RM) -r $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)
	"$(JLINK_HOME)/bin/jlink" \
	 --module-path "$(JLINK_JMODS)$(file_path_sep)$(JLINK_A2_JMODS)" \
	 --add-modules $(JLINK_RT_MODULES),$(subst $(space),$(comma),$(MODULES) $(JLINK_NATIVE_JMODS)) \
	 --output "$(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)"
endef

#
# OS PACKAGES
#
define a2_jpackage_create_msi # (rtName,description,vendor,winUpgradeUuid)	
	"$(JLINK_HOME)/bin/jpackage" \
	 --runtime-image "$(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)" \
	 --type msi \
	 --name "$(1)-$(JLINK_JAVA_RELEASE)-$(JLINK_JVM_VARIANT)" \
	 --app-version $(A2_LAYER_VERSION) \
	 --dest "$(BUILD_BASE)" \
	 --description "$(2)" \
	 --vendor "$(3)" \
	 --license-file "$(SDK_SRC_BASE)/NOTICE" \
	 --win-dir-chooser \
	 --win-per-user-install \
	 --win-upgrade-uuid $(4) \
	 --install-dir "$(1)" \
	
	mv $(BUILD_BASE)/$(1)-$(JLINK_JAVA_RELEASE)-$(JLINK_JVM_VARIANT)-$(A2_LAYER_VERSION).msi \
	 $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)-$(A2_LAYER_VERSION).msi
endef

define a2_jpackage_create_pkg # (rtName,description,vendor)	
# .pkg format does not support versions with more than 3 components
	$(JLINK_HOME)/bin/jpackage \
	 --runtime-image "$(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)" \
	 --type pkg \
	 --name "$(1)-$(JLINK_JAVA_RELEASE)-$(JLINK_JVM_VARIANT)" \
	 --app-version $(major).$(minor).$(micro) \
	 --dest "$(BUILD_BASE)" \
	 --description "$(2)" \
	 --vendor "$(3)" \
	 --license-file "$(SDK_SRC_BASE)/NOTICE" \
	
	mv $(BUILD_BASE)/$(1)-$(JLINK_JAVA_RELEASE)-$(JLINK_JVM_VARIANT)-$(major).$(minor).$(micro).pkg \
	 $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)-$(A2_LAYER_VERSION).pkg
endef

define a2_jpackage_install_pkg # (rtName)	
	sudo installer -store -pkg "$(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)-$(A2_LAYER_VERSION).pkg" -target /
endef
