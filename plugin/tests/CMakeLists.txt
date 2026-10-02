c7_add_test(tst_module SOURCES tst_module.cpp LIBS c7_core Qt6::Qml)
target_compile_definitions(tst_module PRIVATE C7_QML_IMPORT_PATH="${QT_QML_OUTPUT_DIRECTORY}")
# The test loads the plugin at run time, so it has to be built first.
add_dependencies(tst_module c7plugin)
