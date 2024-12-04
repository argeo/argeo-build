cmake_minimum_required(VERSION 3.11) # UseJava features
cmake_minimum_required(VERSION 3.12) # CONFIGURE_DEPENDS in GLOB

if(NOT A2_JAVA_RELEASE)
set(A2_JAVA_RELEASE 17)
endif()
if(NOT A2_CXX_STD)
set(A2_CXX_STD cxx_std_11)
endif()
message (STATUS "A2_JAVA_RELEASE=${A2_JAVA_RELEASE}")

if(NOT A2_OUTPUT)
file(REAL_PATH "../a2" A2_OUTPUT BASE_DIRECTORY	"${CMAKE_BINARY_DIR}")
endif()
message (STATUS "A2_OUTPUT=${A2_OUTPUT}")

if(NOT A2_BASE)
set(A2_BASE ${A2_OUTPUT})
endif()
message (STATUS "A2_BASE=${A2_BASE}")

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

set(A2_TARGET_ARCH_CATEGORY_PREFIX "lib/${A2_TARGET_ARCH}-${A2_TARGET_OS}-${A2_TARGET_CLIB}")
message (STATUS "A2_TARGET_ARCH_CATEGORY_PREFIX=${A2_TARGET_ARCH_CATEGORY_PREFIX}")

# Generates MANIFEST for a bundle
function(a2_osgi_manifest BUNDLE)
	set(MF ${BUNDLE}/META-INF/MANIFEST.MF)

	file(WRITE ${MF} "") # clear
	file(APPEND ${MF} "Manifest-Version: 1.0\nBundle-ManifestVersion: 2\n") # standard
	file(APPEND ${MF} "Bundle-SymbolicName: ${BUNDLE}\n")
	file(APPEND ${MF} "Automatic-Module-Name: ${BUNDLE}\n")
	file(APPEND ${MF} "Bundle-Version: ${CMAKE_PROJECT_VERSION}\n")
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
	endif() # module-info.java exists
	
	# Additional hardcoded directives in bnd.bnd
	if(EXISTS ${PROJECT_SOURCE_DIR}/${BUNDLE}/append.MF)
		file(READ ${PROJECT_SOURCE_DIR}/${BUNDLE}/append.MF CONTENT)
		file(APPEND ${MF} "${CONTENT}")
	endif() # append.MF exists
	
	message (STATUS "Wrote OSGi manifest to ${MF}")
endfunction() # a2_osgi_manifest

# Build a bundle
function(a2_build_bundle BUNDLE)
	a2_osgi_manifest(${BUNDLE})
	file(GLOB_RECURSE JAVA_SRC CONFIGURE_DEPENDS "${BUNDLE}/src/*.java")
	
	message (STATUS "DEP_CATEGORIES=${DEP_CATEGORIES}")
	set(CLASSPATH "")
	foreach(CATEGORY IN LISTS DEP_CATEGORIES)
		message (STATUS "${A2_BASE}/${CATEGORY}/*.jar")
		file(GLOB JARS CONFIGURE_DEPENDS "${A2_BASE}/${CATEGORY}/*.jar")
		list(APPEND CLASSPATH ${JARS})
	endforeach()
	#message (STATUS "CLASSPATH=${CLASSPATH}")
	
	add_jar(${BUNDLE}
		${JAVA_SRC}
		MANIFEST ${BUNDLE}/META-INF/MANIFEST.MF
		INCLUDE_JARS ${CLASSPATH}
		OUTPUT_NAME ${BUNDLE}.${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
		OUTPUT_DIR ${A2_OUTPUT}/${A2_CATEGORY}
		GENERATE_NATIVE_HEADERS ${A2_CATEGORY}-include DESTINATION native/include/${A2_CATEGORY}
	)
	install_jar(${BUNDLE} ${CMAKE_INSTALL_LIBDIR}/a2/${A2_CATEGORY})
endfunction() # a2_build_bundle

# Build a list of bundles
macro(a2_build_bundles BUNDLES)
	message (STATUS "DEP_CATEGORIES=${DEP_CATEGORIES}")
	foreach(BUNDLE IN LISTS BUNDLES)
		a2_build_bundle(${BUNDLE})
	endforeach()
endmacro() # a2_build_bundles

# Configure a JNI target according to A2 conventions
macro(a2_jni_target TARGET)
	target_include_directories(${TARGET} PRIVATE ${JNI_INCLUDE_DIRS})
	target_include_directories(${TARGET} PRIVATE 
		${CMAKE_SOURCE_DIR}/native/include/${A2_CATEGORY})
	set_target_properties(${TARGET} PROPERTIES POSITION_INDEPENDENT_CODE ON)
	target_compile_features(${TARGET} PRIVATE ${A2_CXX_STD})
	set_target_properties(${TARGET} PROPERTIES LIBRARY_OUTPUT_DIRECTORY
		"${A2_OUTPUT}/${A2_TARGET_ARCH_CATEGORY_PREFIX}/${A2_CATEGORY}"
	)
	install(TARGETS ${TARGET}
	LIBRARY DESTINATION lib/${A2_TARGET_ARCH_CATEGORY_PREFIX}/a2/${A2_CATEGORY}
	)
endmacro()

set(ArgeoBuild_FOUND 1)
message (STATUS "Argeo Build configured")
