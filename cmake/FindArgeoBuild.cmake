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

if(NOT JAVA_HOME)
message(FATAL_ERROR "JAVA_HOME must be explicitly set")
endif()

# Java
find_package(Java ${A2_JAVA_RELEASE} REQUIRED COMPONENTS Development)
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

# Actual logic
include(argeo-build)

set(ArgeoBuild_FOUND 1)
message(STATUS "Argeo Build configured")
