#pragma once

#include <QtCore/QCoreApplication>
#include <QtCore/QString>
#include <QtTest/QTest>

namespace c7::testing {

// Cut this process off from the machine it runs on: the D-Bus session and
// system bus addresses point at a socket that does not exist, HOME and the XDG
// directories at a fresh private directory, and the desktop's variables
// (Hyprland, Wayland, X11) are unset. Code that reaches for the host then fails
// instead of quietly using it. C7_TEST_MAIN calls it first thing; it exits the
// process if it cannot set up the private directory.
void isolateFromHost();

// The private directory isolateFromHost() made.
QString hostIsolationRoot();

} // namespace c7::testing

// A QtTest main for every plugin test: isolation first, then the test.
#define C7_TEST_MAIN(TestObject)                                                                   \
    int main(int argc, char *argv[])                                                               \
    {                                                                                              \
        c7::testing::isolateFromHost();                                                            \
        QCoreApplication app(argc, argv);                                                          \
        TestObject tc;                                                                             \
        QTEST_SET_MAIN_SOURCE_PATH                                                                 \
        return QTest::qExec(&tc, argc, argv);                                                      \
    }
