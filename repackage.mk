A2_OUTPUT = $(SDK_BUILD_BASE)/a2
A2_BASE ?= $(A2_OUTPUT)
JVM ?= $(JAVA_HOME)/bin/java

TODOS_REPACKAGE = $(foreach category, $(CATEGORIES),$(BUILD_BASE)/$(category)/to-repackage) 

BUILD_BASE = $(SDK_BUILD_BASE)/$(shell basename $(SDK_SRC_BASE))

all: $(BUILD_BASE)/repackaged 

.SECONDEXPANSION:

# We use .SECONDEXPANSION and CATEGORIES_TO_REPACKAGE instead of directly CATEGORIES
# so that we don't repackage a category if it hasn't changed
$(BUILD_BASE)/repackaged : CATEGORIES_TO_REPACKAGE = $(subst $(abspath $(BUILD_BASE))/,, $(subst to-repackage,, $?))
$(BUILD_BASE)/repackaged : $(TODOS_REPACKAGE)
	$(JVM) \
	 -cp $(A2_BASE)/org.argeo.tp/org.argeo.tp.syslogger.2.3.jar:$(A2_BASE)/org.argeo.tp.sdk/biz.aQute.bndlib.5.3.jar \
	 $(SDK_SRC_BASE)/sdk/argeo-build/src/org/argeo/build/Repackage.java \
	 $(A2_OUTPUT) $(CATEGORIES_TO_REPACKAGE)
	touch $(BUILD_BASE)/repackaged

$(BUILD_BASE)/%/to-repackage : $$(shell find % -type f )
	@rm -rf $(dir $@)
	@mkdir -p $(dir $@) 
	@touch $@

clean:
	$(foreach category, $(CATEGORIES), rm -rf $(A2_OUTPUT)/$(category))
	$(foreach category, $(CATEGORIES), rm -rf $(BUILD_BASE)/$(category))
	rm -f $(BUILD_BASE)/repackaged
