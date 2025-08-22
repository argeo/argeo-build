
CMAKE = cmake

ifeq ($(SDK_BUILD_BASE),)
BUILD_BASE=$(abspath ../output/$(notdir $(CURDIR)))
A2_OUTPUT=$(abspath ../output/a2)
else
BUILD_BASE=$(abspath $(SDK_BUILD_BASE)/$(notdir $(CURDIR)))
endif

# common Makefile path
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8 # Required on Windows

CMAKE_BUILD_TYPE ?= Release


all:
	mkdir -p $(BUILD_BASE)
	$(CMAKE) --build $(BUILD_BASE) -j $(shell nproc)

clean:
	-if [ -d $(BUILD_BASE) ]; then $(CMAKE) --build $(BUILD_BASE) --target clean; fi;

install:
	$(CMAKE) --build $(BUILD_BASE) --target install

describe:
	echo SDK_BUILD_BASE=$(SDK_BUILD_BASE)
	echo BUILD_BASE=$(BUILD_BASE)
	