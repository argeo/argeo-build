# A2 setup
include(argeo-build-setup)

set(TARGET_NATIVE_CATEGORY_PREFIX "${A2_TARGET_ARCH}-${A2_TARGET_OS}-${A2_TARGET_CLIB}")
message(STATUS "TARGET_NATIVE_CATEGORY_PREFIX=${TARGET_NATIVE_CATEGORY_PREFIX}")

# Virtual target for all includes
add_library(${A2_CATEGORY}-includes INTERFACE)
message(STATUS "INCLUDES=${A2_CATEGORY}-includes")

#
# UTILITIES
#

## Generates MANIFEST for a bundle ##
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
		list(APPEND EXPORTED_PKGS ${PCK})
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

## Generates Eclipse source bundle MANIFEST ##
function(a2_osgi_manifest_src BUNDLE)
	set(MF ${BUNDLE}/META-INF/MANIFEST.src.MF)
	
	file(WRITE ${MF} "") # clear
	file(APPEND ${MF} "Manifest-Version: 1.0\nBundle-ManifestVersion: 2\n") # standard
	file(APPEND ${MF} "Bundle-SymbolicName: ${BUNDLE}.src\n")
	file(APPEND ${MF} "Bundle-Version: ${A2_LAYER_VERSION}\n")
	file(APPEND ${MF} "Eclipse-SourceBundle: ${BUNDLE};version=${A2_LAYER_VERSION}\n")
	
	message(STATUS "Wrote Eclipse source manifest to ${MF}")
endfunction() # a2_osgi_manifest_src

## Set result with the list of sources in add_jar RESOURCES format ##
macro(a2_add_sources_as_resources result curdir prefix)
	file(GLOB_RECURSE children LIST_DIRECTORIES false RELATIVE "${curdir}" "${curdir}/*")
	set(packages "")
	
	foreach(child ${children})
		cmake_path(GET child PARENT_PATH dir)
		# add '/' so that root with module-info.java is considered
		list(APPEND packages "/${dir}")
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
endmacro() # a2_add_sources_as_resources

#
# JAVA BUILD
#

## Build a bundle ##
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
	
	# required modules
	file (STRINGS ${BUNDLE}/src/module-info.java REQUIRES_LINES REGEX "requires transitive .*;")
	foreach(LINE IN LISTS REQUIRES_LINES)
		string(REPLACE "requires transitive" "" STRIPPED ${LINE})
		string(STRIP ${STRIPPED} MODULE)
		list(APPEND REQUIRED_MODULES ${MODULE})
	endforeach()

	message(STATUS "REQUIRED_MODULES=${REQUIRED_MODULES}")
	list(LENGTH REQUIRED_MODULES REQUIRED_MODULES_N)	
	if(${REQUIRED_MODULES_N} GREATER 0) 
		string(REPLACE ";" "," REQUIRED_MODULES_STR "${REQUIRED_MODULES}")
		list(APPEND ADD_MODULES "--add-modules")
		list(APPEND ADD_MODULES ${REQUIRED_MODULES_STR})
	endif() # export packages length
	
	# classpath
	set(CLASSPATH "")
	cmake_path(APPEND MODULEPATH_DIRS ${A2_OUTPUT}/${A2_CATEGORY})
	foreach(CATEGORY IN LISTS DEP_CATEGORIES)
		message(STATUS "CLASSPATH += ${A2_BASE}/${CATEGORY}/*.jar")
		file(GLOB JARS CONFIGURE_DEPENDS "${A2_BASE}/${CATEGORY}/*.jar")
		list(APPEND CLASSPATH ${JARS})
		cmake_path(APPEND MODULEPATH_DIRS ${A2_BASE}/${CATEGORY})
	endforeach()
	cmake_path(CONVERT ${MODULEPATH_DIRS} TO_NATIVE_PATH_LIST MODULEPATH)
	message(STATUS "MODULEPATH=${MODULEPATH}")
	
	if(${A2_INSTALL_MODE} STREQUAL "a2")
		set(BUNDLE_OUTPUT_NAME ${BUNDLE}.${A2_major}.${A2_minor})
		set(BUNDLE_INSTALL_DIR ${CMAKE_INSTALL_LIBDIR}/a2/${A2_CATEGORY})
	else() # default is the Debian way
		set(BUNDLE_OUTPUT_NAME ${BUNDLE}-${A2_LAYER_VERSION})
		set(BUNDLE_INSTALL_DIR ${CMAKE_INSTALL_DATADIR}/java)
	endif()
	
	set(CMAKE_JAVA_COMPILE_FLAGS --release ${A2_JAVA_RELEASE} --module-path ${MODULEPATH} ${ADD_MODULES})
	add_jar(${BUNDLE} 
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

## Build a list of bundles ##
macro(a2_build_bundles BUNDLES)
	message(STATUS "DEP_CATEGORIES=${DEP_CATEGORIES}")
	foreach(BUNDLE IN LISTS BUNDLES)
		a2_build_bundle(${BUNDLE})
	endforeach() # BUNDLES
endmacro() # a2_build_bundles

#
# NATIVE BUILD
#

## Configure a JNI target according to A2 conventions ##
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
	
	# TODO simplify/factorize this
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
	
	if(${A2_INSTALL_MODE} STREQUAL "a2")
		install(TARGETS ${TARGET} LIBRARY DESTINATION lib/${CMAKE_LIBRARY_ARCHITECTURE})
	else() # default is the Debian way
		install(TARGETS ${TARGET} LIBRARY DESTINATION lib/${CMAKE_LIBRARY_ARCHITECTURE}/jni)
	endif()
endmacro()
