cmake_minimum_required(VERSION 3.28)
project(HonbakoJavaRuntime LANGUAGES CXX OBJCXX)

set(HONBAKO_RUNTIME_ARTIFACTS "" CACHE PATH "Inspected runtime artifacts outside the repository")
option(HONBAKO_JAVA_RUNTIME_DIAGNOSTICS "Expose the isolated bundled proof entry point" OFF)
string(TOLOWER "${CMAKE_OSX_SYSROOT}" HONBAKO_EXECUTOR_SYSROOT)
if(HONBAKO_EXECUTOR_SYSROOT MATCHES "simulator")
    set(HONBAKO_EXECUTOR_PLATFORM "ios-arm64_x86_64-simulator")
    set(HONBAKO_EXECUTOR_ARCHIVE "libsim.a")
else()
    set(HONBAKO_EXECUTOR_PLATFORM "ios-arm64")
    set(HONBAKO_EXECUTOR_ARCHIVE "libdevice.a")
endif()
set(HONBAKO_EXECUTOR_JDK "${HONBAKO_RUNTIME_ARTIFACTS}/OpenJDK.xcframework/${HONBAKO_EXECUTOR_PLATFORM}")
if(NOT EXISTS "${HONBAKO_EXECUTOR_JDK}/${HONBAKO_EXECUTOR_ARCHIVE}")
    message(FATAL_ERROR "Provide the approved, inspected OpenJDK runtime artifacts")
endif()

add_library(HonbakoJavaExtensionExecutor STATIC HBJavaExtensionExecutor.mm)
target_compile_features(HonbakoJavaExtensionExecutor PRIVATE cxx_std_17)
target_compile_options(HonbakoJavaExtensionExecutor PRIVATE -fobjc-arc)
target_include_directories(HonbakoJavaExtensionExecutor
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}"
    PRIVATE "${HONBAKO_EXECUTOR_JDK}/Headers" "${HONBAKO_EXECUTOR_JDK}/Headers/ios")
target_link_libraries(HonbakoJavaExtensionExecutor PRIVATE
    "${HONBAKO_EXECUTOR_JDK}/${HONBAKO_EXECUTOR_ARCHIVE}"
    "-framework Foundation" "-framework Security" z c++ resolv iconv)
if(HONBAKO_JAVA_RUNTIME_DIAGNOSTICS)
    target_compile_definitions(HonbakoJavaExtensionExecutor PUBLIC HB_JAVA_RUNTIME_DIAGNOSTICS=1)
endif()

# These options must reach the final executable: built-in discovery uses
# dlopen(NULL, RTLD_FIRST)/dlsym on Apple platforms, not a helper dylib.
target_link_options(HonbakoJavaExtensionExecutor INTERFACE "LINKER:-export_dynamic")
foreach(HONBAKO_EXECUTOR_BUILTIN IN ITEMS java zip net nio jimage)
    target_link_options(HonbakoJavaExtensionExecutor INTERFACE "LINKER:-u,_JNI_OnLoad_${HONBAKO_EXECUTOR_BUILTIN}")
endforeach()

# The consuming app owns resources and must set ENABLE_DEBUG_DYLIB=NO. Package
# the verified image at <app>/lib/lib/modules and selected config at lib/conf.
# Fixed application classpath resources are honbako-extension-bridge.jar and
# komga-proof-dependencies.jar; diagnostics additionally require RuntimeProbe.jar.
