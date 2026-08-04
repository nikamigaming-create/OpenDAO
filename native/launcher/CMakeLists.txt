cmake_minimum_required(VERSION 3.20)
project(OpenDAOLauncher LANGUAGES CXX)

add_executable(OpenDAO WIN32 main.cpp)
target_compile_features(OpenDAO PRIVATE cxx_std_17)
target_compile_definitions(OpenDAO PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
