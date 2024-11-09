cmake_minimum_required(VERSION 3.11) # UseJava features
cmake_minimum_required(VERSION 3.12) # CONFIGURE_DEPENDS in GLOB

if(NOT A2_JAVA_RELEASE)
set(A2_JAVA_RELEASE 17)
endif()
message (STATUS "A2_JAVA_RELEASE=${A2_JAVA_RELEASE}")

# Java
find_package(Java ${A2_JAVA_RELEASE} REQUIRED)
include(UseJava)
set(CMAKE_JAVA_COMPILE_FLAGS "--release" "${A2_JAVA_RELEASE}")
if (Java_FOUND)
    message (STATUS "Java_JAVA_EXECUTABLE=${Java_JAVA_EXECUTABLE}")
    message (STATUS "Java_VERSION_MAJOR=${Java_VERSION_MAJOR}")
endif()

# JNI
find_package(JNI)
if (JNI_FOUND)
    message (STATUS "JNI_INCLUDE_DIRS=${JNI_INCLUDE_DIRS}")
    message (STATUS "JNI_LIBRARIES=${JNI_LIBRARIES}")
endif()

# supported OSes
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
	set(A2_TARGET_OS "linux")
	set(A2_TARGET_ARCH ${CMAKE_SYSTEM_PROCESSOR})
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

if(NOT A2_TARGET_OS)
	set(A2_TARGET_OS ${CMAKE_SYSTEM_NAME})
endif()
if(NOT A2_TARGET_ARCH)
	set(A2_TARGET_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()

set(A2_TARGET_ARCH_CATEGORY_PREFIX "lib/${A2_TARGET_OS}/${A2_TARGET_ARCH}")
message (STATUS "A2_TARGET_ARCH_CATEGORY_PREFIX=${A2_TARGET_ARCH_CATEGORY_PREFIX}")

function(a2_osgi_manifest BUNDLE)
	set(MF ${BUNDLE}/META-INF/MANIFEST.MF)

	file(WRITE ${MF} "") # clear
	file(APPEND ${MF} "Manifest-Version: 1.0\nBundle-ManifestVersion: 2\n") # standard
	file(APPEND ${MF} "Bundle-SymbolicName: ${BUNDLE}\n")
	file(APPEND ${MF} "Bundle-Version: ${CMAKE_PROJECT_VERSION}\n")
	file(APPEND ${MF} "Bundle-RequiredExecutionEnvironment: JavaSE-${A2_JAVA_RELEASE}\n")
	
	# exported packages, based on module-info.java
	file (STRINGS ${BUNDLE}/src/module-info.java LINES REGEX "exports .*;")
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
	
	# Additional hardcoded directives in bnd.bnd
	file(READ ${BUNDLE}/bnd.bnd BND_CONTENT)
	file(APPEND ${MF} "${BND_CONTENT}")
	
	message (STATUS "Wrote OSGi manifest to ${MF}")
endfunction() # a2_osgi_manifest

function(a2_build_bundle BUNDLE)
	a2_osgi_manifest(${BUNDLE})
	file(GLOB_RECURSE JAVA_SRC CONFIGURE_DEPENDS "${BUNDLE}/src/*.java")
	string(REPLACE "." "_" BUNDLE_NATIVE ${BUNDLE})
	add_jar(${BUNDLE}
		${JAVA_SRC}
		MANIFEST ${BUNDLE}/META-INF/MANIFEST.MF
		OUTPUT_NAME ${BUNDLE}.${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
		OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/../a2/${A2_CATEGORY}
		GENERATE_NATIVE_HEADERS ${BUNDLE_NATIVE}-include DESTINATION jni/include/${BUNDLE_NATIVE}
)
endfunction() # a2_build_bundle

function(a2_build_bundles BUNDLES)
	foreach(BUNDLE IN LISTS BUNDLES)
		a2_build_bundle(${BUNDLE})
	endforeach()
endfunction() # a2_build_bundles

set(ArgeoBuild_FOUND 1)
message (STATUS "Argeo Build configured")
