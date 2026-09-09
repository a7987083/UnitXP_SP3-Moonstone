cmake_minimum_required(VERSION 3.20)
project(ZonoeLocalAuthPhase4BackendReplace LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(ZonoeLocalAuthPhase4BackendReplace SHARED
    src/ZonoeBackendReplace.mm
)

target_compile_options(ZonoeLocalAuthPhase4BackendReplace PRIVATE -fobjc-arc)
target_link_libraries(ZonoeLocalAuthPhase4BackendReplace PRIVATE "-framework Foundation" objc)

set_target_properties(ZonoeLocalAuthPhase4BackendReplace PROPERTIES
    OUTPUT_NAME "ZonoeLocalAuth_Phase4_BackendReplace"
    PREFIX ""
    SUFFIX ".dylib"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
)
