# Convenience Makefile based on default Argeo SDK conventions
# TODO make it compatible with sdk.mk
BUILD_BASE=$(abspath ../output/$(notdir $(CURDIR)))
A2_OUTPUT=$(abspath ../output/a2)

# common Makefile path
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8 # Required on Windows

CMAKE_BUILD_TYPE ?= RelWithDebInfo


all:
	mkdir -p $(BUILD_BASE)
	cmake -B $(BUILD_BASE) . -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)
	cmake --build $(BUILD_BASE) -j $(shell nproc)

clean:
	if [ -d $(BUILD_BASE) ]; then cmake --build $(BUILD_BASE) --target clean; fi;

install:
	cmake --build ../output/$(BUILD_BASE) --target install
