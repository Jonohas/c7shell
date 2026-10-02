add_library(c7_core STATIC version.h version.cpp)
target_include_directories(c7_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(c7_core PUBLIC Qt6::Core)
target_compile_definitions(c7_core PRIVATE C7_VERSION="${PROJECT_VERSION}")

add_executable(tst_version tests/tst_version.cpp)
target_link_libraries(tst_version PRIVATE c7_core Qt6::Test)
target_compile_definitions(tst_version PRIVATE C7_EXPECTED_VERSION="${PROJECT_VERSION}")
add_test(NAME tst_version COMMAND tst_version)
