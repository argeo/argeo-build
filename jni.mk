ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk

# The following variables should be declared in the including Makefile:
# NATIVE_PACKAGE    this native package name
# A2_CATEGORY       the (single) a2 category the bundles will belong to

# The following variables have default values which can be overriden
# DEP_NATIVE        space-separated logical names of named depdencies
# DEP_INCLUDES      additional includes
# DEP_LIBS          additional native libraries
DEP_NATIVE ?=
DEP_INCLUDES ?= $(foreach dep, $(DEP_NATIVE), /usr/include/$(dep))
DEP_LIBS ?= $(foreach dep, $(DEP_NATIVE), -l$(dep))

A2_NATIVE_CATEGORY=$(A2_OUTPUT)/lib/linux/$(shell uname -m)/$(A2_CATEGORY)
TARGET_EXEC := libJava_$(NATIVE_PACKAGE).so

LDFLAGS ?= -shared -fPIC -Wl,-soname,$(TARGET_EXEC).$(MAJOR).$(MINOR) $(DEP_LIBS)
CFLAGS ?= -O3 -fPIC

SRC_DIRS := . 

#
# Generic Argeo
#
BUILD_DIR := $(SDK_BUILD_BASE)/jni/$(NATIVE_PACKAGE)

# Include directories
INC_DIRS := $(shell find $(SRC_DIRS) -type d) $(JAVA_HOME)/include $(JAVA_HOME)/include/linux $(DEP_INCLUDES)

all: $(A2_NATIVE_CATEGORY)/$(TARGET_EXEC)

clean:
	$(RM) $(BUILD_DIR)/*.o
	$(RM) $(A2_NATIVE_CATEGORY)/$(TARGET_EXEC)

install:
	$(INSTALL) $(A2_NATIVE_INSTALL_TARGET) $(A2_NATIVE_CATEGORY)/$(TARGET_EXEC)

uninstall:
	$(RM) $(A2_NATIVE_INSTALL_TARGET)/$(TARGET_EXEC)
	@if [ -d $(A2_NATIVE_INSTALL_TARGET) ]; then find $(A2_NATIVE_INSTALL_TARGET) -empty -type d -delete; fi

# Sources
SRCS := $(shell find $(SRC_DIRS) -name '*.cpp' -or -name '*.c' -or -name '*.s')
# Objects (example.cpp to ./org_example_core/example.cpp.o)
OBJS := $(SRCS:%=$(BUILD_DIR)/%.o)
# Dependencies (example.cpp.o to ./org_example_core/example.cpp.d)
DEPS := $(OBJS:.o=.d)
# Add -I prefix to include directories
INC_FLAGS := $(addprefix -I,$(INC_DIRS))
# Generate dependencies makefiles
CPPFLAGS := $(INC_FLAGS) -MMD -MP

# Final build step
$(A2_NATIVE_CATEGORY)/$(TARGET_EXEC): $(OBJS)
	mkdir -p $(A2_NATIVE_CATEGORY)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

# Build step for C source
$(BUILD_DIR)/%.c.o: %.c
	mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

# Build step for C++ source
$(BUILD_DIR)/%.cpp.o: %.cpp
	mkdir -p $(dir $@)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

# Include the .d makefiles. (- pefix suppress errors if not found)
-include $(DEPS)

.PHONY: clean all install uninstall
