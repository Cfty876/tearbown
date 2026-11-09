cmake_minimum_required(VERSION 3.17)

# voxcore: native voxel core for the Teardown-like prototype.
# Hot paths live here: meshing, collision boxes, carving, island detection.

set(GODOTCPP_TARGET "template_release" CACHE STRING "")
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "")

project(voxcore LANGUAGES CXX)

if(EMSCRIPTEN)
    set(GODOTCPP_THREADS OFF CACHE BOOL "" FORCE)
    set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/web-profile.json" CACHE PATH "")
    set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)
endif()

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../tools/godot-cpp ${CMAKE_BINARY_DIR}/godot-cpp)

file(GLOB VOXCORE_SOURCES CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp ${CMAKE_CURRENT_SOURCE_DIR}/src/*.h)
add_library(voxcore SHARED ${VOXCORE_SOURCES})
target_link_libraries(voxcore PRIVATE godot-cpp)

set(OUTPUT_DIR "${CMAKE_BINARY_DIR}/out/")

set_target_properties(
    voxcore
    PROPERTIES
        CXX_STANDARD 17
        CXX_EXTENSIONS OFF
        POSITION_INDEPENDENT_CODE ON
        LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        PDB_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        OUTPUT_NAME "voxcore"
)

if(MSVC)
    target_compile_options(voxcore PRIVATE /O2 /Oi /fp:fast /W3 /wd4244 /wd4267 /wd4305)
endif()

if(EMSCRIPTEN)
    set_target_properties(voxcore PROPERTIES PREFIX "" SUFFIX ".wasm")
    target_link_options(voxcore PRIVATE -sSIDE_MODULE=2 "-sEXPORTED_FUNCTIONS=_voxcore_init")
endif()
