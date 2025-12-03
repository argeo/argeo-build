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
JLINK_A2_JMODS=$(A2_JMODS)/$(JLINK_JAVA_RELEASE)
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

define a2_jmod_create_native # (moduleName)
	$(RM) $(JLINK_A2_JMODS)/$(TARGET_NATIVE_CATEGORY_PREFIX)-$(1).jmod
	mkdir -p $(JLINK_A2_JMODS)
	
	"$(JLINK_HOME)/bin/jmod" create \
	 --class-path "$(JMODS_BASE)/$(1)/classes" \
	 --target-platform "$(JMOD_TARGET_PLATFORM)" \
	 --config "$(JMODS_BASE)/$(1)/config" \
	 --man-pages "$(JMODS_BASE)/$(1)/man" \
	 --legal-notices "$(JMODS_BASE)/$(1)/legal" \
	 --libs "$(JMODS_BASE)/$(1)/lib" \
	 --cmds "$(JMODS_BASE)/$(1)/bin" \
	 --header-files "$(JMODS_BASE)/$(1)/include" \
	 "$(JLINK_A2_JMODS)/$(TARGET_NATIVE_CATEGORY_PREFIX)-$(1).jmod"
	
	# list content
	"$(JLINK_HOME)/bin/jmod" list "$(JLINK_A2_JMODS)/$(TARGET_NATIVE_CATEGORY_PREFIX)-$(1).jmod"
endef

#
# JDK/JRE CREATION
#
define a2_jlink_create_jdk # (jdkName)	
	$(RM) -r $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)
	"$(JLINK_HOME)/bin/jlink" \
	 --module-path "$(JLINK_JMODS)$(file_path_sep)$(JLINK_A2_JMODS)" \
	 --add-modules $(JLINK_RT_MODULES),$(JLINK_JAVA_MODULES),$(subst $(space),$(comma),$(MODULES) $(JLINK_NATIVE_JMODS)) \
	 --output "$(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)"
	
	cp $(JLINK_HOME)/lib/src.zip $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/lib
	
	mkdir -p $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src
	$(foreach module,$(MODULES),cp -r $(module)/src $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src/$(module))
	"$(JLINK_HOME)/bin/jar" -u -f $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/lib/src.zip \
	 -C $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src $(MODULES)
	$(RM) -r $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/src
	
	mkdir -p $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/jmods
	$(foreach module,$(MODULES) $(JLINK_NATIVE_JMODS),\
	 $(COPY) $(JLINK_A2_JMODS)/*$(module).jmod $(BUILD_BASE)/$(1)-$(JLINK_SUFFIX)/jmods; \
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

#
# MINIMAL OS DEPENDENCIES
#

# Minimal required OS libs for distribution
A2_OS_LIBS_CATEGORY=org.argeo.os.libs
JMOD_OS_LIBS=$(A2_OS_LIBS_CATEGORY)

ifeq ($(MSYS_VERSION),0)
ifeq ($(HOST_OS),linux)
A2_OS_LIBS=\
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/ld-linux-x86-64.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libc.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libstdc++.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libz.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libm.so.* \
/usr/lib/$(TARGET_NATIVE_CATEGORY_PREFIX)/libgcc_s.so.*

# TODO make it more robust
A2_OS_LIBS_VERSION = $(shell gcc -dumpversion).0.0
endif
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
ifneq ($(A2_OS_LIBS),)
	cp $(A2_OS_LIBS) $(TARGET_NATIVE_OUTPUT)/$(A2_OS_LIBS_CATEGORY)
endif
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

