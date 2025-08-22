# Convenience Makefile based on default Argeo SDK conventions
# TODO make it compatible with sdk.mk
#BUILD_BASE=$(abspath ../output/$(notdir $(CURDIR)))
#A2_OUTPUT=$(abspath ../output/a2)

ifeq ($(SDK_BUILD_BASE),)
BUILD_BASE=$(abspath ../output/$(notdir $(CURDIR)))
A2_OUTPUT=$(abspath ../output/a2)
else
BUILD_BASE=$(abspath $(SDK_BUILD_BASE)/$(notdir $(CURDIR)))
endif

# common Makefile path
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8 # Required on Windows

CMAKE_BUILD_TYPE ?= RelWithDebInfo


all:
	mkdir -p $(BUILD_BASE)
	cmake --build $(BUILD_BASE) -j $(shell nproc)

clean:
	-if [ -d $(BUILD_BASE) ]; then cmake --build $(BUILD_BASE) --target clean; fi;

install:
	cmake --build $(BUILD_BASE) --target install

describe:
	echo SDK_BUILD_BASE=$(SDK_BUILD_BASE)
	echo BUILD_BASE=$(BUILD_BASE)
	