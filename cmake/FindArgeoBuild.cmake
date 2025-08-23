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
file(REAL_PATH "${Java_JAVA_EXECUTABLE}/../.." JAVA_HOME)
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
        OUTPUT_VARIABLE GitRevCount
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    set(A2_qualifier ".${GitRevCount}" CACHE INTERNAL A2_qualifier)
endif()
endif()
endfunction()

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

if(NOT A2_BASE)
set(A2_BASE ${A2_OUTPUT})
endif()
message(STATUS "A2_BASE=${A2_BASE}")

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
	endif()
endif()

if(MINGW)
   # cmake ../../ -DCMAKE_INSTALL_PREFIX=$MINGW_PREFIX
   set(CMAKE_SHARED_LIBRARY_PREFIX "")
endif() # MINGW

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

macro(a2_list_packages result curdir)
	file(GLOB_RECURSE children LIST_DIRECTORIES false RELATIVE "${curdir}" "${curdir}/*")
	set(packages "")
	foreach(child ${children})
		cmake_path(GET child PARENT_PATH dir)
		list(APPEND packages "/${dir}")
		message(STATUS "/${dir}")
	endforeach()
	list(REMOVE_DUPLICATES packages)
	set(${result} ${packages})
endmacro()

# Build a bundle
function(a2_build_bundle BUNDLE)
	a2_osgi_manifest(${BUNDLE})
	file(GLOB_RECURSE JAVA_SRC CONFIGURE_DEPENDS "${BUNDLE}/src/*.java")
	
	# resources and embedded sources
	set(RESOURCES "")
	a2_list_packages(namespaces "${CMAKE_SOURCE_DIR}/${BUNDLE}/src")
	message(STATUS "namespaces=${namespaces}")
	foreach(namespace ${namespaces})
		set(lst "")
		list(APPEND RESOURCES "NAMESPACE")
		list(APPEND RESOURCES "OSGI-INF/src${namespace}")
		file(GLOB files "${BUNDLE}/src${namespace}/*")
		foreach(file ${files})
			list(APPEND RESOURCES "${file}")
		endforeach()
	endforeach()
	
	set(CLASSPATH "")
	foreach(CATEGORY IN LISTS DEP_CATEGORIES)
		message(STATUS "CLASSPATH += ${A2_BASE}/${CATEGORY}/*.jar")
		file(GLOB JARS CONFIGURE_DEPENDS "${A2_BASE}/${CATEGORY}/*.jar")
		list(APPEND CLASSPATH ${JARS})
	endforeach()
	
	# !! CMAKE_JAVA_COMPILE_FLAGS must be first
	add_jar(${BUNDLE}
		CMAKE_JAVA_COMPILE_FLAGS "--release ${A2_JAVA_RELEASE}"
		SOURCES ${JAVA_SRC}
		RESOURCES ${RESOURCES}
		INCLUDE_JARS ${CLASSPATH}
		MANIFEST ${BUNDLE}/META-INF/MANIFEST.MF
		OUTPUT_NAME ${BUNDLE}.${A2_major}.${A2_minor}
		OUTPUT_DIR ${A2_OUTPUT}/${A2_CATEGORY}
		GENERATE_NATIVE_HEADERS ${BUNDLE}-include DESTINATION ${CMAKE_SOURCE_DIR}/native/include/${A2_CATEGORY}
	)
	add_dependencies(${A2_CATEGORY}-includes ${BUNDLE}-include)
	install_jar(${BUNDLE} ${CMAKE_INSTALL_LIBDIR}/a2/${A2_CATEGORY})
endfunction() # a2_build_bundle

# Build a list of bundles
macro(a2_build_bundles BUNDLES)
	message(STATUS "DEP_CATEGORIES=${DEP_CATEGORIES}")
	foreach(BUNDLE IN LISTS BUNDLES)
		a2_build_bundle(${BUNDLE})
	endforeach()
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
	else()
		set_target_properties(${TARGET} PROPERTIES LIBRARY_OUTPUT_DIRECTORY
			"${A2_OUTPUT}/lib/${TARGET_NATIVE_CATEGORY_PREFIX}/${A2_CATEGORY}")
	endif()
	install(TARGETS ${TARGET} LIBRARY DESTINATION lib/${CMAKE_LIBRARY_ARCHITECTURE})
endmacro()

set(ArgeoBuild_FOUND 1)
message(STATUS "Argeo Build configured")
