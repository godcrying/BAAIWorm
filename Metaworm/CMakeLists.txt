cmake_minimum_required(VERSION 2.8.6)
project(metaworm)

add_compile_options(-fPIC)
add_compile_options(-std=gnu++14)
add_compile_options(-Wdeprecated-declarations)
if(NOT WIN32)
  add_compile_options(-include cassert)
endif()

add_definitions(-DSOFTCON_DIR="${PROJECT_SOURCE_DIR}")
set(CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake_module")

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING
      "Choose the type of build, options are: Debug Release
RelWithDebInfo MinSizeRel."
      FORCE)
endif(NOT CMAKE_BUILD_TYPE)

add_subdirectory( sim )
add_subdirectory( render )
add_subdirectory( interact )

set(META_WORM_INCLUDES 
    ${WORM_RENDER_INCLUDES}
    ${WORM_INTERACT_INCLUDES}
    ${WORM_SIM_INCLUDES} PARENT_SCOPE)

file(COPY args data DESTINATION ${CMAKE_BINARY_DIR})
