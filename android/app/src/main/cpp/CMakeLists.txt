cmake_minimum_required(VERSION 3.18.1)

project("niooom_native_engine" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(
    niooom_native_engine
    SHARED
    niooom_stream_engine.cpp
)

find_library(
    log-lib
    log
)

target_compile_options(
    niooom_native_engine
    PRIVATE
    -O3
    -ffast-math
    -fvisibility=hidden
    -Wall
)

target_link_libraries(
    niooom_native_engine
    ${log-lib}
)
