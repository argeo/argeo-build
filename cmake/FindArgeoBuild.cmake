cmake_minimum_required(VERSION 3.11) # UseJava features
cmake_minimum_required(VERSION 3.12) # CONFIGURE_DEPENDS in GLOB
cmake_minimum_required(VERSION 3.20) # DESTINATION in JNI GENERATE_NATIVE_HEADERS

if(NOT A2_CATEGORY)
message(FATAL_ERROR "Variable A2_CATEGORY must be set")
endif()

if(NOT A2_JAVA_RELEASE)
set(A2_JAVA_RELEASE 17)
endif()
if(NOT A2_CXX_STD)
set(A2_CXX_STD cxx_std_17)
endif()
message(STATUS "A2_JAVA_RELEASE=${A2_JAVA_RELEASE}")

# Java
find_package(Java ${A2_JAVA_RELEASE} REQUIRED)
include(UseJava)
set(CMAKE_JAVA_COMPILE_FLAGS "--release" "${A2_JAVA_RELEASE}")
if (Java_FOUND)
message(STATUS "Java_JAVA_EXECUTABLE=${Java_JAVA_EXECUTABLE}")
message(STATUS "Java_VERSION_MAJOR=${Java_VERSION_MAJOR}")
endif()

# JNI
find_package(JNI REQUIRED)
if (JNI_FOUND)
message(STATUS "JNI_INCLUDE_DIRS=${JNI_INCLUDE_DIRS}")
message(STATUS "JNI_LIBRARIES=${JNI_LIBRARIES}")
endif()

if(NOT JAVA_HOME)
# TODO check whether it is actually working
file(REAL_PATH "${Java_JAVA_EXECUTABLE}" Java_JAVA_EXECUTABLE_SymLinksResolved)
file(REAL_PATH "${Java_JAVA_EXECUTABLE_SymLinksResolved}/../.." JAVA_HOME)
message(STATUS "JAVA_HOME=${JAVA_HOME}")
endif()

# Git
find_package(Git)
#
# ARGEO BUILD COMPATIBILITY
#

function(a2_read_properties PATH PREFIX)
# from https://stackoverflow.com/a/17168870
file(STRINGS ${PATH} ConfigContents)
foreach(NameAndValue ${ConfigContents})
# Strip leading spaces
string(REGEX REPLACE "^[ ]+" "" NameAndValue ${NameAndValue})
# Find variable name
string(REGEX MATCH "^[^=]+" Name ${NameAndValue})
# Find the value
string(REPLACE "${Name}=" "" Value ${NameAndValue})
# Set the variable
set(${PREFIX}${Name} "${Value}" CACHE INTERNAL ${PREFIX}${Name})
endforeach()
endfunction() # read_properties

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

file(WRITE ${CMAKE_SOURCE_DIR}/sdk.mk "SDK_SRC_BASE=${SDK_SRC_BASE}\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "SDK_BUILD_BASE=${SDK_BUILD_BASE}\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "JAVA_HOME=${SDK_JAVA_HOME}\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "-include branch.mk\n")
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "-include sdk/branches/$(BRANCH).bnd\n")

if(MINGW)
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "export SDK_BUILD_BASE_WIN=${SDK_BUILD_BASE_WIN}\n")
elseif(MSVC)
file(APPEND ${CMAKE_SOURCE_DIR}/sdk.mk "export SDK_BUILD_BASE_WIN=${SDK_BUILD_BASE_WIN}\n")
endif()

a2_read_properties(${CMAKE_SOURCE_DIR}/branch.mk "A2_")
a2_read_properties(${CMAKE_SOURCE_DIR}/sdk/branches/${A2_BRANCH}.bnd "A2_")
a2_replace_next_qualifier()
set(A2_LAYER_VERSION "${A2_major}.${A2_minor}.${A2_micro}${A2_qualifier}")
message(STATUS "Branch: ${A2_BRANCH} - Version: ${A2_LAYER_VERSION}")

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
set(A2_TARGET_CLIB "gnu")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
set(A2_TARGET_OS "macosx")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
set(A2_TARGET_OS "win32")
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "AMD64")
set(A2_TARGET_ARCH "x86_64")
endif() # CMAKE_SYSTEM_PROCESSOR
endif() # CMAKE_SYSTEM_NAME

if(MINGW)
set(CMAKE_SHARED_LIBRARY_PREFIX "")
endif()

# defaults
if(NOT A2_TARGET_OS)
set(A2_TARGET_OS ${CMAKE_SYSTEM_NAME})
endif()
if(NOT A2_TARGET_ARCH)
set(A2_TARGET_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()
if(NOT A2_TARGET_CLIB)
set(A2_TARGET_CLIB "default")
endif()

set(TARGET_NATIVE_CATEGORY_PREFIX "${A2_TARGET_ARCH}-${A2_TARGET_OS}-${A2_TARGET_CLIB}")
message(STATUS "TARGET_NATIVE_CATEGORY_PREFIX=${TARGET_NATIVE_CATEGORY_PREFIX}")

# Virtual target for all includes
add_library(${A2_CATEGORY}-includes INTERFACE)
message(STATUS "INCLUDES=${A2_CATEGORY}-includes")

#
# UTILITIES
#

# Generates MANIFEST for a bundle
function(a2_osgi_manifest BUNDLE)
set(MF ${BUNDLE}/META-INF/MANIFEST.MF)

file(WRITE ${MF} "") # clear
file(APPEND ${MF} "Manifest-Version: 1.0\nBundle-ManifestVersion: 2\n") # standard
file(APPEND ${MF} "Bundle-SymbolicName: ${BUNDLE}\n")
file(APPEND ${MF} "Bundle-Version: ${A2_LAYER_VERSION}\n")
file(APPEND ${MF} "Bundle-RequiredExecutionEnvironment: JavaSE-${A2_JAVA_RELEASE}\n")

# exported packages, based on module-info.java
if(EXISTS ${PROJECT_SOURCE_DIR}/${BUNDLE}/src/module-info.java)
file (STRINGS ${PROJECT_SOURCE_DIR}/${BUNDLE}/src/module-info.java LINES REGEX "exports .*;")

foreach(LINE IN LISTS LINES)
string(REPLACE "exports" "" STRIPPED ${LINE})
string(STRIP ${STRIPPED} PCK)
LIST(APPEND EXPORTED_PKGS ${PCK})
endforeach()

list(LENGTH EXPORTED_PKGS EXPORTED_PKGS_N)

if(${EXPORTED_PKGS_N} GREATER 0) 
string(REPLACE ";" ",\n " EXPORT_PACKAGE "${EXPORTED_PKGS}")
file(APPEND ${MF} "Export-Package: ${EXPORT_PACKAGE}\n")
endif() # export packages length

else()
	file(APPEND ${MF} "Automatic-Module-Name: ${BUNDLE}\n")
endif() # module-info.java exists

# Additional hardcoded directives in bnd.bnd
if(EXISTS ${PROJECT_SOURCE_DIR}/${BUNDLE}/append.MF)
file(READ ${PROJECT_SOURCE_DIR}/${BUNDLE}/append.MF CONTENT)
file(APPEND ${MF} "${CONTENT}")
endif() # append.MF exists

message(STATUS "Wrote OSGi manifest to ${MF}")
endfunction() # a2_osgi_manifest

# Generates Eclipse source bundle MANIFEST
function(a2_osgi_manifest_src BUNDLE)
set(MF ${BUNDLE}/META-INF/MANIFEST.src.MF)

file(WRITE ${MF} "") # clear
file(APPEND ${MF} "Manifest-Version: 1.0\nBundle-ManifestVersion: 2\n") # standard
file(APPEND ${MF} "Bundle-SymbolicName: ${BUNDLE}.src\n")
file(APPEND ${MF} "Bundle-Version: ${A2_LAYER_VERSION}\n")
file(APPEND ${MF} "Eclipse-SourceBundle: ${BUNDLE};version=${A2_LAYER_VERSION}\n")

message(STATUS "Wrote Eclipse source manifest to ${MF}")
endfunction() # a2_osgi_manifest

# Set result with the list of sources in add_jar RESOURCES format
macro(a2_add_sources_as_resources result curdir prefix)
file(GLOB_RECURSE children LIST_DIRECTORIES false RELATIVE "${curdir}" "${curdir}/*")
set(packages "")

foreach(child ${children})
cmake_path(GET child PARENT_PATH dir)
# add '/' so that root with module-info.java is considered
list(APPEND packages "/${dir}")
#message(STATUS "/${dir}")
endforeach()

list(REMOVE_DUPLICATES packages)
set(resources "")

foreach(package ${packages})
list(APPEND resources "NAMESPACE")
list(APPEND resources "${prefix}${package}")
file(GLOB files LIST_DIRECTORIES false "${curdir}${package}/*")
foreach(file ${files})
list(APPEND resources "${file}")
endforeach() # files
endforeach() # packages

set(${result} ${resources})
endmacro()

# Build a bundle
function(a2_build_bundle BUNDLE)
a2_osgi_manifest(${BUNDLE})
file(GLOB_RECURSE JAVA_SRC CONFIGURE_DEPENDS "${BUNDLE}/src/*.java")

# sources as resources
string(TOLOWER "$ENV{SOURCE_BUNDLES}" check_source_bundles)

if(NOT "${check_source_bundles}" STREQUAL "true")
a2_add_sources_as_resources(SOURCES_AS_RESOURCES
 "${CMAKE_SOURCE_DIR}/${BUNDLE}/src"
 "OSGI-INF/src")
else() # separate source bundles
a2_add_sources_as_resources(SRC_AS_RESOURCES
 "${CMAKE_SOURCE_DIR}/${BUNDLE}/src"
 ".")

a2_osgi_manifest_src(${BUNDLE})
add_jar(${BUNDLE}.src
 SOURCES
 RESOURCES ${SRC_AS_RESOURCES}
 MANIFEST ${BUNDLE}/META-INF/MANIFEST.src.MF
 OUTPUT_NAME ${BUNDLE}.${A2_major}.${A2_minor}.src
 OUTPUT_DIR ${A2_SRC_OUTPUT}/${A2_CATEGORY}
)
endif() # check_source_bundles

# compilation
set(CLASSPATH "")
foreach(CATEGORY IN LISTS DEP_CATEGORIES)
message(STATUS "CLASSPATH += ${A2_BASE}/${CATEGORY}/*.jar")
file(GLOB JARS CONFIGURE_DEPENDS "${A2_BASE}/${CATEGORY}/*.jar")
list(APPEND CLASSPATH ${JARS})
endforeach()

# !! CMAKE_JAVA_COMPILE_FLAGS must be first
if(${A2_INSTALL_MODE} STREQUAL "a2")
set(BUNDLE_OUTPUT_NAME ${BUNDLE}.${A2_major}.${A2_minor})
set(BUNDLE_INSTALL_DIR ${CMAKE_INSTALL_LIBDIR}/a2/${A2_CATEGORY})
else() # default is the Debian way
set(BUNDLE_OUTPUT_NAME ${BUNDLE}-${A2_LAYER_VERSION})
set(BUNDLE_INSTALL_DIR ${CMAKE_INSTALL_DATADIR}/java)
endif()

add_jar(${BUNDLE}
 CMAKE_JAVA_COMPILE_FLAGS "--release ${A2_JAVA_RELEASE}"
 SOURCES ${JAVA_SRC}
 RESOURCES ${SOURCES_AS_RESOURCES}
 INCLUDE_JARS ${CLASSPATH}
 MANIFEST ${BUNDLE}/META-INF/MANIFEST.MF
 OUTPUT_NAME ${BUNDLE_OUTPUT_NAME}
 OUTPUT_DIR ${A2_OUTPUT}/${A2_CATEGORY}
 GENERATE_NATIVE_HEADERS ${BUNDLE}-include
  DESTINATION ${CMAKE_SOURCE_DIR}/native/include/${A2_CATEGORY}
)
add_dependencies(${A2_CATEGORY}-includes ${BUNDLE}-include)
install_jar(${BUNDLE} ${BUNDLE_INSTALL_DIR})
endfunction() # a2_build_bundle

# Build a list of bundles
macro(a2_build_bundles BUNDLES)
message(STATUS "DEP_CATEGORIES=${DEP_CATEGORIES}")
foreach(BUNDLE IN LISTS BUNDLES)
a2_build_bundle(${BUNDLE})
endforeach() # BUNDLES
endmacro() # a2_build_bundles

# Configure a JNI target according to A2 conventions
macro(a2_jni_target TARGET)
# JNI
target_include_directories(${TARGET} PRIVATE ${JNI_INCLUDE_DIRS})
# local includes (possibly git submodules)
target_include_directories(${TARGET} PRIVATE ${CMAKE_SOURCE_DIR}/native/include/)
# generated include files
add_dependencies(${TARGET} ${A2_CATEGORY}-includes)
target_include_directories(${TARGET} PRIVATE 
 ${CMAKE_SOURCE_DIR}/native/include/${A2_CATEGORY})
set_target_properties(${TARGET} PROPERTIES
 POSITION_INDEPENDENT_CODE ON
 VERSION ${A2_LAYER_VERSION}
 SOVERSION ${A2_major}
)
target_compile_features(${TARGET} PRIVATE ${A2_CXX_STD})
if(MINGW)
# bin is used as output directory in MSYS
set_target_properties(${TARGET} PROPERTIES RUNTIME_OUTPUT_DIRECTORY
 "${A2_OUTPUT}/lib/${TARGET_NATIVE_CATEGORY_PREFIX}/${A2_CATEGORY}")
set_target_properties(${TARGET} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY
 "${A2_OUTPUT}/lib/${TARGET_NATIVE_CATEGORY_PREFIX}/${A2_CATEGORY}")
elseif(MSVC)
# bin is used as output directory in MSVC
set_target_properties(${TARGET} PROPERTIES RUNTIME_OUTPUT_DIRECTORY
 $<1:${A2_OUTPUT}/lib/${TARGET_NATIVE_CATEGORY_PREFIX}/${A2_CATEGORY}>)
set_target_properties(${TARGET} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY
 $<1:${A2_OUTPUT}/lib/${TARGET_NATIVE_CATEGORY_PREFIX}/${A2_CATEGORY}>)
else()
set_target_properties(${TARGET} PROPERTIES LIBRARY_OUTPUT_DIRECTORY
 "${A2_OUTPUT}/lib/${TARGET_NATIVE_CATEGORY_PREFIX}/${A2_CATEGORY}")
endif() # MINGW

install(TARGETS ${TARGET} LIBRARY DESTINATION lib/${CMAKE_LIBRARY_ARCHITECTURE}/jni)
endmacro()

set(ArgeoBuild_FOUND 1)
message(STATUS "Argeo Build configured")

