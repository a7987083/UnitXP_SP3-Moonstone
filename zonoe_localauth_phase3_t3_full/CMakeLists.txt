cmake_minimum_required(VERSION 3.20)
project(ZonoeLocalAuthPhase3T3Full LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(ZonoeLocalAuthPhase3T3Full SHARED
    src/ZonoeAuthAdapter.mm
)

target_include_directories(ZonoeLocalAuthPhase3T3Full PRIVATE include)
target_compile_options(ZonoeLocalAuthPhase3T3Full PRIVATE -fobjc-arc)
target_link_libraries(ZonoeLocalAuthPhase3T3Full PRIVATE "-framework Foundation" objc)

set_target_properties(ZonoeLocalAuthPhase3T3Full PROPERTIES
    OUTPUT_NAME "ZonoeLocalAuth_Phase3_T3_Full"
    PREFIX ""
    SUFFIX ".dylib"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
)
