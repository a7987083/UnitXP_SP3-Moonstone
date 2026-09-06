cmake_minimum_required(VERSION 3.20)
project(Login10195Diag LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Disable Xcode signing for every target, including the statically linked Dobby target.
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")

set(DOBBY_GENERATE_SHARED OFF CACHE BOOL "" FORCE)
set(DOBBY_DEBUG OFF CACHE BOOL "" FORCE)
set(DOBBY_BUILD_EXAMPLE OFF CACHE BOOL "" FORCE)
set(DOBBY_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(Plugin.SymbolResolver OFF CACHE BOOL "" FORCE)
set(Plugin.ImportTableReplace OFF CACHE BOOL "" FORCE)

if(NOT EXISTS "${CMAKE_SOURCE_DIR}/third_party/Dobby/CMakeLists.txt")
  message(FATAL_ERROR "third_party/Dobby missing; CI clones it before configure")
endif()

add_subdirectory(third_party/Dobby Dobby-build)

add_library(Login10195Diag SHARED
  src/Login10195Diag.cpp
)

target_include_directories(Login10195Diag PRIVATE
  ${CMAKE_SOURCE_DIR}/third_party/Dobby/include
)

target_link_libraries(Login10195Diag PRIVATE dobby)

target_compile_options(Login10195Diag PRIVATE
  -fvisibility=hidden
  -fno-exceptions
  -fno-rtti
)

set_target_properties(Login10195Diag PROPERTIES
  PREFIX ""
  SUFFIX ".dylib"
  OUTPUT_NAME "Login10195Diag_v0.1"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
  XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
  XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
)
