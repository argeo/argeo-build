ARGEO_BUILD_BASE := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)

ifneq ($(MSYS_VERSION),0) # MSYS
ifneq (,$(VCIDEInstallDir))
MSVC_IDE_BASE=$(shell cygpath -m '$(VCIDEInstallDir)\\..')
else
MSVC_IDE_BASE=$(shell cygpath -m 'C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/Common7/IDE/')
endif
MSVC_CMAKE_BASE=$(MSVC_IDE_BASE)CommonExtensions/Microsoft/CMake
MSVC_CMAKE="$(MSVC_CMAKE_BASE)/CMake/bin/cmake.exe"
ifeq ($(MSYSTEM),MSYS) # Use MSVC when no full MSYS toolchain available
CMAKE ?= $(MSVC_CMAKE)
endif
endif # MSYS

# Must be after MSVC checks
CMAKE ?= cmake

ifeq ($(SDK_SRC_BASE),)
SDK_SRC_BASE=$(abspath $(ARGEO_BUILD_BASE)/../..)
SDK_BUILD_BASE=$(abspath $(SDK_SRC_BASE)/../output)
A2_OUTPUT=$(abspath $(SDK_BUILD_BASE)/a2)
endif
BUILD_BASE=$(abspath $(SDK_BUILD_BASE)/$(notdir $(SDK_SRC_BASE)))

# common Makefile path
include $(dir $(lastword $(MAKEFILE_LIST)))../common.mk

export JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF8 # Required on Windows

A2_INSTALL_MODE ?= a2
A2_BUILD_INDEP_ONLY ?= OFF

CMAKE_BUILD_TYPE ?= Release

cmake-all:
	cmake -B $(BUILD_BASE) . \
	 -DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
	 -DA2_INSTALL_MODE=$(A2_INSTALL_MODE) \
	 -DA2_BUILD_INDEP_ONLY=$(A2_BUILD_INDEP_ONLY) \
	 -DJAVA_HOME=$(JAVA_HOME)
	$(CMAKE) --build $(BUILD_BASE) --config $(CMAKE_BUILD_TYPE) -j $(shell nproc)

cmake-clean:
	-if [ -d $(BUILD_BASE) ]; then $(CMAKE) --build $(BUILD_BASE) --target clean; fi;

cmake-distclean:
	$(RM) -r $(BUILD_BASE)
	$(RM) sdk.mk

cmake-install:
	$(CMAKE) --build $(BUILD_BASE) --target install

cmake-check:
ifeq ($(CMAKE),$(MSVC_CMAKE))
	$(CMAKE) --build $(BUILD_BASE) --target RUN_TESTS
else
	$(CMAKE) --build $(BUILD_BASE) --target test
endif

cmake-describe:
	echo SDK_SRC_BASE=$(SDK_SRC_BASE)
	echo SDK_BUILD_BASE=$(SDK_BUILD_BASE)
	echo BUILD_BASE=$(BUILD_BASE)
	echo JAVA_HOME=$(JAVA_HOME)
	echo A2_OUTPUT=$(A2_OUTPUT)

.PHONY: cmake-all cmake-clean cmake-distclean cmake-install cmake-describe
