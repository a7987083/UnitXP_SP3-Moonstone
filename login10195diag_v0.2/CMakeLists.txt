cmake_minimum_required(VERSION 3.20)
project(Login10195DiagV02 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")

set(DOBBY_DEBUG OFF CACHE BOOL "" FORCE)
set(DOBBY_BUILD_EXAMPLE OFF CACHE BOOL "" FORCE)
set(DOBBY_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(Plugin.SymbolResolver ON CACHE BOOL "" FORCE)
set(Plugin.ImportTableReplace OFF CACHE BOOL "" FORCE)

if(NOT EXISTS "${CMAKE_SOURCE_DIR}/third_party/Dobby/CMakeLists.txt")
  message(FATAL_ERROR "third_party/Dobby missing; CI clones it before configure")
endif()

add_subdirectory(third_party/Dobby Dobby-build)

add_library(Login10195DiagV02 SHARED
  src/Login10195DiagV02.cpp
)

target_include_directories(Login10195DiagV02 PRIVATE
  ${CMAKE_SOURCE_DIR}/third_party/Dobby/include
)

target_link_libraries(Login10195DiagV02 PRIVATE
  dobby_static
  "-lobjc"
)

target_compile_options(Login10195DiagV02 PRIVATE
  -fvisibility=hidden
  -fno-exceptions
  -fno-rtti
)

set_target_properties(Login10195DiagV02 PROPERTIES
  PREFIX ""
  SUFFIX ".dylib"
  OUTPUT_NAME "Login10195Diag_v0.2"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
  XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
  XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
)
