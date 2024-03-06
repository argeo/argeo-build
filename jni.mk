ARGEO_BUILD_BASE := $(dir $(lastword $(MAKEFILE_LIST)))
include $(ARGEO_BUILD_BASE)common.mk

A2_NATIVE_CATEGORY=$(A2_OUTPUT)/lib/linux/$(shell uname -m)/$(A2_CATEGORY)
TARGET_EXEC := libJava_$(NATIVE_PACKAGE).so

LDFLAGS = -shared -fPIC -Wl,-soname,$(TARGET_EXEC).$(MAJOR).$(MINOR) $(ADDITIONAL_LIBS)
CFLAGS = -O3 -fPIC

SRC_DIRS := . 

#
# Generic Argeo
#
BUILD_DIR := $(SDK_BUILD_BASE)/jni/$(NATIVE_PACKAGE)

# Include directories
INC_DIRS := $(shell find $(SRC_DIRS) -type d) $(JAVA_HOME)/include $(JAVA_HOME)/include/linux $(ADDITIONAL_INCLUDES)

all: $(A2_NATIVE_CATEGORY)/$(TARGET_EXEC)

clean:
	$(RM) $(BUILD_DIR)/*.o
	$(RM) $(A2_NATIVE_CATEGORY)/$(TARGET_EXEC)

install:
	$(CP) $(A2_NATIVE_CATEGORY)/$(TARGET_EXEC) $(A2_NATIVE_INSTALL_TARGET)

uninstall:
	$(RM) $(A2_NATIVE_INSTALL_TARGET)/$(TARGET_EXEC)

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
