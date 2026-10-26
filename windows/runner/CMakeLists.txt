cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# The executable file is named BINARY_NAME. The target id has no spaces.
#
# Any new source files that you add to the application should be added here.
add_executable(${RUNNER_TARGET} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

set_target_properties(${RUNNER_TARGET} PROPERTIES OUTPUT_NAME "${BINARY_NAME}")

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${RUNNER_TARGET})

# Add preprocessor definitions for the build version.
target_compile_definitions(${RUNNER_TARGET} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${RUNNER_TARGET} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${RUNNER_TARGET} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${RUNNER_TARGET} PRIVATE "dwmapi.lib")
target_include_directories(${RUNNER_TARGET} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${RUNNER_TARGET} flutter_assemble)
