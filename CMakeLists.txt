cmake_minimum_required(VERSION 3.0)

set(CMAKE_CXX_STANDARD 17)

project(spirv-to-pica200)

add_subdirectory(externals/SPIRV-Headers)

set(SPIRV-Headers_SOURCE_DIR ${CMAKE_SOURCE_DIR}/externals/SPIRV-Headers)
add_subdirectory(externals/SPIRV-Tools)

add_executable(spirv-to-pica200 src/main.cpp)

target_include_directories(spirv-to-pica200 PRIVATE ${CMAKE_SOURCE_DIR}/SPIRV-Tools/include)

target_link_libraries(spirv-to-pica200 PUBLIC SPIRV-Tools)
