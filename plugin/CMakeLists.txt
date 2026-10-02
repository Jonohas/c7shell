cmake_minimum_required(VERSION 3.21)
project(c7 VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# The libraries are static and linked into the QML plugin, a shared module.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Qml Test)
qt_standard_project_setup(REQUIRES 6.5)

# Every QML module lands under one directory, so a test imports from it alone.
set(QT_QML_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/qml)

enable_testing()

# Plain C++ libraries: Qt Core, Network and DBus only, never QML.
add_subdirectory(lib/core)

# The C7 QML module: contracts in src/contracts/, backends in src/backends/.
# The backing target is the plugin, so one library in qml/C7/ is the whole
# module. NO_PLUGIN_OPTIONAL, because nothing links that library: the engine
# has to load it, and an optional plugin is one it skips.
qt_add_qml_module(c7
    URI C7
    VERSION 1.0
    PLUGIN_TARGET c7
    NO_PLUGIN_OPTIONAL
    SOURCES src/build.h
)
# The generated type registration includes each header by its bare name.
target_include_directories(c7 PRIVATE src)
target_link_libraries(c7 PRIVATE c7_core)

# Installed where Qt finds every system QML module, /usr/lib/qt6/qml/C7 on Arch.
set(c7_qml_dir ${QT6_INSTALL_QML}/C7)
install(TARGETS c7 LIBRARY DESTINATION ${c7_qml_dir})
install(FILES ${QT_QML_OUTPUT_DIRECTORY}/C7/qmldir ${QT_QML_OUTPUT_DIRECTORY}/C7/c7.qmltypes
    DESTINATION ${c7_qml_dir})

add_subdirectory(tests)
