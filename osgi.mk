

#
# GENERIC
#
JVM := $(JAVA_HOME)/bin/java
JAVADOC := $(JAVA_HOME)/bin/javadoc
ECJ_JAR := $(A2_BASE)/org.argeo.tp.sdk/org.eclipse.jdt.core.compiler.batch.3.29.jar
BNDLIB_JAR := $(A2_BASE)/org.argeo.tp.sdk/biz.aQute.bndlib.5.3.jar
SLF4J_API_JAR := $(A2_BASE)/org.argeo.tp/org.slf4j.api.1.7.jar

#ARGEO_MAKE = $(JVM) -cp $(ECJ_JAR):$(BNDLIB_JAR):$(SLF4J_API_JAR):$(BUILD_BASE)/bin org/argeo/build/Make
ARGEO_MAKE := $(JVM) -cp $(ECJ_JAR):$(BNDLIB_JAR):$(SLF4J_API_JAR) $(SDK_SRC_BASE)/sdk/argeo-build/src/org/argeo/build/Make.java
#BND_TOOL := /usr/bin/bnd

BUILD_BASE = $(SDK_BUILD_BASE)/$(shell basename $(SDK_SRC_BASE))

#WORKSPACE_BNDS := $(shell cd $(SDK_SRC_BASE) && find cnf -name '*.bnd') sdk/argeo-build/argeo.bnd
#BUILD_WORKSPACE_BNDS := $(WORKSPACE_BNDS:%=$(BUILD_BASE)/%)

#A2_JARS = $(foreach category, $(DEP_CATEGORIES), $(shell find $(A2_BASE)/$(category) -name '*.jar'))
#A2_CLASSPATH = $(subst $(space),$(pathsep),$(strip $(A2_JARS)))

#A2_BUNDLES = $(foreach bundle, $(BUNDLES),$(A2_OUTPUT)/$(A2_CATEGORY)/$(shell basename $(bundle)).$(MAJOR).$(MINOR).jar)

#JAVA_SRCS = $(foreach bundle, $(BUNDLES), $(shell find $(bundle) -name '*.java'))
#BNDS = $(foreach bundle, $(BUNDLES), $(BUILD_BASE)/$(shell basename $(bundle))/bnd.bnd)
#ECJ_SRCS = $(foreach bundle, $(BUNDLES), $(bundle)/src[-d $(BUILD_BASE)/$(bundle)/bin])

JAVADOC_SRCS = $(foreach bundle, $(JAVADOC_BUNDLES),$(bundle)/src)

osgi: $(BUILD_BASE)/built

javadoc: $(BUILD_BASE)/java-compiled
	$(JAVADOC) -d $(BUILD_BASE)/api --source-path $(subst $(space),$(pathsep),$(strip $(JAVADOC_SRCS))) -subpackages $(JAVADOC_PACKAGES)


TARGET_BUNDLES :=  $(abspath $(foreach bundle, $(BUNDLES),$(A2_OUTPUT)/$(shell dirname $(bundle))/$(A2_CATEGORY)/$(shell basename $(bundle)).$(MAJOR).$(MINOR).jar))
TODOS := $(foreach bundle, $(BUNDLES),$(BUILD_BASE)/$(bundle)/to-build) 

.SECONDEXPANSION:

$(BUILD_BASE)/built : BUNDLES_TO_BUILD = $(subst $(abspath $(BUILD_BASE))/,, $(subst to-build,, $?))
$(BUILD_BASE)/built : $(TODOS)
	$(ARGEO_MAKE) all --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) --category $(A2_CATEGORY) --bundles $(BUNDLES_TO_BUILD)
	touch $(BUILD_BASE)/built 

$(A2_OUTPUT)/%.$(MAJOR).$(MINOR).jar : $(BUILD_BASE)/$$(subst $(A2_CATEGORY)/,,$$*)/to-build
	$(ARGEO_MAKE) all --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) --category $(A2_CATEGORY) --bundles $(subst $(A2_CATEGORY)/,,$*)

$(BUILD_BASE)/%/to-build : $$(shell find $(SDK_SRC_BASE)/% -type f -not -path 'bin/*' -not -path '*/MANIFEST.MF')
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@) 
	@touch $@

$(BUILD_BASE)/%/sources-modified : $$(shell find $(SDK_SRC_BASE)/$$* -name '*.java')
	touch $@	

$(BUILD_BASE)/%/java-compiled: $(BUILD_BASE)/%/sources-modified
	$(ARGEO_MAKE) compile --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) --bundles $(BUNDLES)
	touch $@	

# Build level
$(BUILD_BASE)/jars-built: $(BUILD_BASE)/java-compiled 
	$(ARGEO_MAKE) bundle --category $(A2_CATEGORY) --bundles $(BUNDLES)
	touch $@

$(BUILD_BASE)/java-compiled : $(JAVA_SRCS)
	$(ARGEO_MAKE) compile --a2-bases $(A2_BASE) --dep-categories $(DEP_CATEGORIES) --bundles $(BUNDLES)
	touch $@

clean-a2 :
	rm -rf $(TARGET_BUNDLES)
	rm -rf $(BUILD_BASE)/built

# Local manifests
manifests : osgi
	@mkdir -p $(foreach bundle, $(BUNDLES), $(bundle)/META-INF/);
	@$(foreach bundle, $(BUNDLES), cp -v $(BUILD_BASE)/$(bundle)/META-INF/MANIFEST.MF  $(bundle)/META-INF/MANIFEST.MF;)
	
builder: $(BUILD_BASE)/bin/org/argeo/build/Make.class

$(BUILD_BASE)/bin/org/argeo/build/Make.class : $(SDK_SRC_BASE)/sdk/argeo-build/java/org/argeo/build/Make.java
	$(JVM) -jar $(ECJ_JAR) -cp $(ECJ_JAR):$(BNDLIB_JAR):$(SLF4J_API_JAR) @$(SDK_SRC_BASE)/sdk/argeo-build/ecj.args $(SDK_SRC_BASE)/sdk/argeo-build/src[-d $(BUILD_BASE)/bin]

null  :=
space := $(null) #
pathsep := :
