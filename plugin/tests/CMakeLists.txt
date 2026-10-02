add_executable(tst_module tst_module.cpp)
target_link_libraries(tst_module PRIVATE c7_core Qt6::Qml Qt6::Test)
target_compile_definitions(tst_module PRIVATE C7_QML_IMPORT_PATH="${QT_QML_OUTPUT_DIRECTORY}")
# The test loads the plugin at run time, so it has to be built first.
add_dependencies(tst_module c7)
add_test(NAME tst_module COMMAND tst_module)
