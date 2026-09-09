cmake_minimum_required(VERSION 3.20)
project(ZonoeLocalAuthPhase4DualMode LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(ZonoeLocalAuthPhase4DualMode SHARED
    src/ZonoeBackendDualMode.mm
)

target_compile_options(ZonoeLocalAuthPhase4DualMode PRIVATE -fobjc-arc)
target_link_libraries(ZonoeLocalAuthPhase4DualMode PRIVATE
    "-framework Foundation"
    "-framework UIKit"
    "-framework QuartzCore"
    objc
)

set_target_properties(ZonoeLocalAuthPhase4DualMode PROPERTIES
    OUTPUT_NAME "ZonoeLocalAuth_Phase4_DualMode"
    PREFIX ""
    SUFFIX ".dylib"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
)
