#
# Common build routines to be included in Makefiles
#
# The following variables are found in the sdk.mk file which is generated by the configure script:
# SDK_SRC_BASE		the base of the source code, typically the root of the cloned git repository
# SDK_BUILD_BASE	the base of the output
# JAVA_HOME			the base of the JDK used to build
A2_OUTPUT := $(SDK_BUILD_BASE)/a2
JVM ?= $(JAVA_HOME)/bin/java
JAVADOC ?= $(JAVA_HOME)/bin/javadoc

# The following variables should be declared in the Makefile:
# BUNDLES			the space-separated list of bundles to be built
# A2_CATEGORY		the a2 category the bundles will belong to
#
# The following variables have default values which can be overriden in the Makefile
# DEP_CATEGORIES	the a2 categories the compilation depends on
# JAVADOC_PACKAGES	the space-separated list of packages for which javadoc will be generated
# A2_BASE			the space-separated directories where already built a2 categories can be found
DEP_CATEGORIES ?=
JAVADOC_PACKAGES ?=
A2_BASE ?= $(A2_OUTPUT)

ECJ_JAR ?= $(A2_BASE)/org.argeo.tp.build/org.eclipse.jdt.core.compiler.batch.3.32.jar
BNDLIB_JAR ?= $(A2_BASE)/org.argeo.tp.build/biz.aQute.bndlib.5.3.jar
ARGEO_MAKE := $(JVM) -cp $(ECJ_JAR):$(BNDLIB_JAR) $(SDK_SRC_BASE)/sdk/argeo-build/src/org/argeo/build/Make.java
#ARGEO_MAKE = $(JVM) -cp $(ECJ_JAR):$(BNDLIB_JAR):$(SLF4J_API_JAR):$(BUILD_BASE)/bin org/argeo/build/Make

JAVADOC_SRCS = $(foreach bundle, $(BUNDLES), $(bundle)/src)

BUILD_BASE = $(SDK_BUILD_BASE)/$(shell basename $(SDK_SRC_BASE))

TARGET_BUNDLES =  $(abspath $(foreach bundle, $(BUNDLES),$(A2_OUTPUT)/$(shell dirname $(bundle))/$(A2_CATEGORY)/$(shell basename $(bundle)).$(major).$(minor).jar))
TODOS = $(foreach bundle, $(BUNDLES),$(BUILD_BASE)/$(bundle)/to-build) 

## Needed in order to be able to expand $$ variables
.SECONDEXPANSION:
.PHONY: osgi manifests javadoc

osgi: $(BUILD_BASE)/built

javadoc: $(BUILD_BASE)/built
	$(JAVADOC) -quiet -Xmaxwarns 1 -d $(BUILD_BASE)/api --source-path $(subst $(space),$(pathsep),$(strip $(JAVADOC_SRCS))) -subpackages $(JAVADOC_PACKAGES)

# Actual build (compilation + bundle packaging)
$(BUILD_BASE)/built : BUNDLES_TO_BUILD = $(subst $(abspath $(BUILD_BASE))/,, $(subst to-build,, $?))
$(BUILD_BASE)/built : $(TODOS)
	$(ARGEO_MAKE) all --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) --category $(A2_CATEGORY) --bundles $(BUNDLES_TO_BUILD)
	touch $(BUILD_BASE)/built 

$(A2_OUTPUT)/%.$(major).$(minor).jar : $(BUILD_BASE)/$$(subst $(A2_CATEGORY)/,,$$*)/to-build
	$(ARGEO_MAKE) all --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) --category $(A2_CATEGORY) --bundles $(subst $(A2_CATEGORY)/,,$*)

$(BUILD_BASE)/%/to-build : $$(shell find % -type f -not -path 'bin/*' -not -path '*/MANIFEST.MF' | sed 's/ /\\ /g')
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@) 
	@touch $@

# Local manifests
manifests : osgi
	@mkdir -p $(foreach bundle, $(BUNDLES), $(bundle)/META-INF/);
	@$(foreach bundle, $(BUNDLES), cp -v $(BUILD_BASE)/$(bundle)/META-INF/MANIFEST.MF  $(bundle)/META-INF/MANIFEST.MF;)

# Local build of the builder, not used as the performance gain is negligible	
builder: $(BUILD_BASE)/bin/org/argeo/build/Make.class

$(BUILD_BASE)/bin/org/argeo/build/Make.class : $(SDK_SRC_BASE)/sdk/argeo-build/java/org/argeo/build/Make.java
	$(JVM) -jar $(ECJ_JAR) -cp $(ECJ_JAR):$(BNDLIB_JAR):$(SLF4J_API_JAR) @$(SDK_SRC_BASE)/sdk/argeo-build/ecj.args $(SDK_SRC_BASE)/sdk/argeo-build/src[-d $(BUILD_BASE)/bin]

# Make variables used to replace spaces by a separator, typically in order to generate classpaths
# for example: CLASSPATH = $(subst $(space),$(pathsep),$(strip $(JARS)))
null  :=
space := $(null) #
pathsep := :