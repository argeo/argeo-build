ARGEO_BUILD_BASE := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)

CMAKE = cmake

ifeq ($(SDK_SRC_BASE),)
SDK_SRC_BASE=$(abspath $(ARGEO_BUILD_BASE)/../..)
SDK_BUILD_BASE=$(abspath $(SDK_SRC_BASE)/../output)
A2_OUTPUT=$(abspath $(SDK_BUILD_BASE)/a2)
endif
BUILD_BASE=$(abspath $(SDK_BUILD_BASE)/$(notdir $(SDK_SRC_BASE)))

# common Makefile path
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8 # Required on Windows

CMAKE_BUILD_TYPE ?= Release

all:
	cmake -B $(BUILD_BASE) . -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE)
	$(CMAKE) --build $(BUILD_BASE) -j $(shell nproc)

clean:
	-if [ -d $(BUILD_BASE) ]; then $(CMAKE) --build $(BUILD_BASE) --target clean; fi;

distclean:
	$(RM) -r $(BUILD_BASE)
	$(RM) sdk.mk

install:
	$(CMAKE) --build $(BUILD_BASE) --target install

describe:
	echo SDK_SRC_BASE=$(SDK_SRC_BASE)
	echo SDK_BUILD_BASE=$(SDK_BUILD_BASE)
	echo BUILD_BASE=$(BUILD_BASE)

.PHONY: configure all clean install describe
