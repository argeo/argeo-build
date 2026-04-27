# Git
find_package(Git)

#
# UTILITIES
#

## Read simple equals-separated key/value properties ## 
function(a2_read_properties PATH PREFIX)
	# from https://stackoverflow.com/a/17168870
	file(STRINGS ${PATH} ConfigContents)
	foreach(NameAndValue ${ConfigContents})
		string(REGEX REPLACE "^[ ]+" "" NameAndValue ${NameAndValue})
		string(REGEX MATCH "^[^=]+" Name ${NameAndValue})
		string(REPLACE "${Name}=" "" Value ${NameAndValue})
		set(${PREFIX}${Name} "${Value}" CACHE INTERNAL ${PREFIX}${Name})
	endforeach()
endfunction() # read_properties

## Replace .next qualifier ##
function(a2_replace_next_qualifier)
	if(A2_qualifier STREQUAL ".next")
	if (Git_FOUND)
		execute_process(COMMAND "${GIT_EXECUTABLE}" rev-list --count ${A2_major}.${A2_minor}.${A2_micro}..HEAD
		 WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		 OUTPUT_VARIABLE GitRevCount OUTPUT_STRIP_TRAILING_WHITESPACE)
		if(NOT "${GitRevCount}" STREQUAL "") # will also be empty if not a working copy
			execute_process(COMMAND "${GIT_EXECUTABLE}" rev-parse --short=7 HEAD
			 WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			 OUTPUT_VARIABLE GitShortHash OUTPUT_STRIP_TRAILING_WHITESPACE)
			if(GitRevCount LESS 10)
			set(GitRevCountPadded "000${GitRevCount}")
			elseif(GitRevCount LESS 100)
			set(GitRevCountPadded "00${GitRevCount}")
			elseif(GitRevCount LESS 1000)
			set(GitRevCountPadded "0${GitRevCount}")
			else()
			set(GitRevCountPadded "${GitRevCount}")
			endif() # GitRevCountPadded
			set(A2_qualifier ".${GitRevCountPadded}-${GitShortHash}" CACHE INTERNAL A2_qualifier)
		endif() # GitRevCount
	endif() # Git_FOUND
	endif() # A2_qualifier
endfunction() # a2_replace_next_qualifier

# Normalize MinGW paths
if(MINGW)
file(REAL_PATH ".." SDK_BUILD_BASE_WIN BASE_DIRECTORY "${CMAKE_BINARY_DIR}")
execute_process(COMMAND cygpath -u ${SDK_BUILD_BASE_WIN} OUTPUT_VARIABLE SDK_BUILD_BASE OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND cygpath -u ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE SDK_SRC_BASE OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND cygpath -u ${JAVA_HOME} OUTPUT_VARIABLE SDK_JAVA_HOME OUTPUT_STRIP_TRAILING_WHITESPACE)
else()
file(REAL_PATH ".." SDK_BUILD_BASE BASE_DIRECTORY "${CMAKE_BINARY_DIR}")
set(SDK_SRC_BASE ${CMAKE_SOURCE_DIR})
set(SDK_JAVA_HOME ${JAVA_HOME})
endif()

# Generate sdk.mk file for Argeo Build Make compatibility
# TODO make it more robust
file(WRITE ${CMAKE_SOURCE_DIR}/sdk.mk "SDK_SRC_BASE := ${SDK_SRC_BASE}\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "SDK_BUILD_BASE ?= ${SDK_BUILD_BASE}\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "JAVA_HOME ?= ${SDK_JAVA_HOME}\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "-include branch.mk\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "-include sdk/branches/$(BRANCH).bnd\n")

if(MINGW)
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "export SDK_BUILD_BASE_WIN=${SDK_BUILD_BASE_WIN}\n")
elseif(MSVC)
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "export SDK_BUILD_BASE_WIN=${SDK_BUILD_BASE_WIN}\n")
endif()

# Compute version
a2_read_properties(${CMAKE_SOURCE_DIR}/branch.mk "A2_")
a2_read_properties(${CMAKE_SOURCE_DIR}/sdk/branches/${A2_BRANCH}.bnd "A2_")
a2_replace_next_qualifier()
set(A2_LAYER_VERSION "${A2_major}.${A2_minor}.${A2_micro}${A2_qualifier}")
message(STATUS "Branch: ${A2_BRANCH} - Version: ${A2_LAYER_VERSION}")
if("${A2_qualifier}" STREQUAL "")
set(A2_RELEASING ON)
message(STATUS "Releasing A2 layer")
else()
set(A2_RELEASING OFF)
endif()

if(NOT A2_OUTPUT)
set(A2_OUTPUT ${SDK_BUILD_BASE}/a2)
endif()
message(STATUS "A2_OUTPUT=${A2_OUTPUT}")

if(NOT A2_SRC_OUTPUT)
set(A2_SRC_OUTPUT ${SDK_BUILD_BASE}/a2.src)
endif()

if(NOT A2_BASE)
set(A2_BASE ${A2_OUTPUT})
endif()
message(STATUS "A2_BASE=${A2_BASE}")

if(NOT A2_INSTALL_MODE)
set(A2_INSTALL_MODE default)
endif()
message(STATUS "A2_INSTALL_MODE=${A2_INSTALL_MODE}")

#
# OS SPECIFIC
#

# Use GNU conventions
include(GNUInstallDirs)

# supported OSes
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
set(A2_TARGET_OS "linux")
set(A2_TARGET_ARCH ${CMAKE_SYSTEM_PROCESSOR})
set(A2_TARGET_OS_LIBS "gnu")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(A2_TARGET_OS "macos")
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
set(A2_TARGET_ARCH "aarch64")
endif() # CMAKE_SYSTEM_PROCESSOR
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
set(A2_TARGET_OS "windows")
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64")
set(A2_TARGET_ARCH "x86_64")
endif() # CMAKE_SYSTEM_PROCESSOR
endif() # CMAKE_SYSTEM_NAME

if(MINGW)
set(CMAKE_SHARED_LIBRARY_PREFIX "")
if($ENV{MSYSTEM} STREQUAL "CLANG64")
set(A2_TARGET_OS_LIBS "llvm")
else()
set(A2_TARGET_OS_LIBS "gnu")
endif()
endif()

# defaults
if(NOT A2_TARGET_OS)
set(A2_TARGET_OS ${CMAKE_SYSTEM_NAME})
endif()
if(NOT A2_TARGET_ARCH)
set(A2_TARGET_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()
if(NOT A2_TARGET_OS_LIBS)
set(A2_TARGET_OS_LIBS "std")
endif()
