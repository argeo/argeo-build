

#
# GENERIC
#
JVM := $(JAVA_HOME)/bin/java
JAVADOC := $(JAVA_HOME)/bin/javadoc
ECJ_JAR := $(A2_BASE)/org.argeo.tp.sdk/org.eclipse.jdt.core.compiler.batch.3.28.jar
BND_TOOL := /usr/bin/bnd

BUILD_BASE = $(SDK_BUILD_BASE)/$(A2_CATEGORY)

WORKSPACE_BNDS := $(shell cd $(SDK_SRC_BASE) && find cnf -name '*.bnd')
BUILD_WORKSPACE_BNDS := $(WORKSPACE_BNDS:%=$(BUILD_BASE)/%)

A2_JARS = $(foreach category, $(DEP_CATEGORIES), $(shell find $(A2_BASE)/$(category) -name '*.jar'))
A2_CLASSPATH = $(subst $(space),$(pathsep),$(strip $(A2_JARS)))

A2_BUNDLES = $(foreach bundle, $(BUNDLES),$(A2_OUTPUT)/$(A2_CATEGORY)/$(shell basename $(bundle)).$(MAJOR).$(MINOR).jar)

JAVA_SRCS = $(foreach bundle, $(BUNDLES), $(shell find $(bundle) -name '*.java'))
BNDS = $(foreach bundle, $(BUNDLES), $(BUILD_BASE)/$(shell basename $(bundle))/bnd.bnd)
ECJ_SRCS = $(foreach bundle, $(BUNDLES), $(bundle)/src[-d $(BUILD_BASE)/$(shell basename $(bundle))/bin])

JAVADOC_SRCS = $(foreach bundle, $(JAVADOC_BUNDLES),$(bundle)/src)

osgi: $(BUILD_WORKSPACE_BNDS) $(A2_BUNDLES)

javadoc: $(BUILD_BASE)/java-compiled
	$(JAVADOC) -d $(BUILD_BASE)/api --source-path $(subst $(space),$(pathsep),$(strip $(JAVADOC_SRCS))) -subpackages $(JAVADOC_PACKAGES)


# SDK level
$(BUILD_BASE)/cnf/%.bnd: cnf/%.bnd
	mkdir -p $(dir $@)
	cp $< $@
	
$(A2_OUTPUT)/$(A2_CATEGORY)/%.$(MAJOR).$(MINOR).jar : $(BUILD_BASE)/%.jar
	mkdir -p $(dir $@)
	cp $< $@

$(BUILD_BASE)/%.jar: $(BUILD_BASE)/jars-built
	mv $(basename $@)/generated/*.jar $(basename $@).jar

# Build level
$(BUILD_BASE)/jars-built: $(BNDS)
	cd $(BUILD_BASE) && $(BND_TOOL) build
	touch $@

$(BUILD_BASE)/%/bnd.bnd : %/bnd.bnd $(BUILD_BASE)/java-compiled 
	mkdir -p $(dir $@)bin
	rsync -r --exclude "*.java" $(dir  $<)src/ $(dir $@)bin
	rsync -r --exclude-from $(SDK_SRC_BASE)/sdk/excludes.txt $(dir  $<) $(dir $@)bin
	if [ -d "$(dir  $<)OSGI-INF" ]; then rsync -r $(dir  $<)OSGI-INF/ $(dir $@)/OSGI-INF; fi
	cp $< $@
	echo "\n-sourcepath:$(SDK_SRC_BASE)/$(dir  $<)src\n" >> $@

$(BUILD_BASE)/java-compiled : $(JAVA_SRCS)
	$(JVM) -jar $(ECJ_JAR) @$(SDK_SRC_BASE)/sdk/ecj.args -cp $(A2_CLASSPATH) $(ECJ_SRCS)
	touch $@

# Local manifests
manifests : osgi
	$(foreach bundle, $(BUNDLES), cp -v $(BUILD_BASE)/$(shell basename $(bundle))/META-INF/MANIFEST.MF  $(bundle)/META-INF/MANIFEST.MF;)

null  :=
space := $(null) #
pathsep := :
