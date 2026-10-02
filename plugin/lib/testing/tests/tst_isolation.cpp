#include "testing/privatebus.h"
#include "testing/testmain.h"

#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtDBus/QDBusConnection>
#include <QtTest/QTest>

// C7_TEST_MAIN cuts the test off from the host before anything runs, so a
// library or fixture that reaches for the real buses, sockets or runtime
// directory fails instead of quietly using the machine's.
class TestIsolation : public QObject {
    Q_OBJECT

private slots:
    void theHostSessionBusIsUnreachable() { QVERIFY(!QDBusConnection::sessionBus().isConnected()); }

    void theHostSystemBusIsUnreachable() { QVERIFY(!QDBusConnection::systemBus().isConnected()); }

    void runtimeAndHomeDirectoriesArePrivate_data()
    {
        QTest::addColumn<QByteArray>("var");
        for (const char *v : {"XDG_RUNTIME_DIR", "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
                              "XDG_CACHE_HOME", "XDG_STATE_HOME"})
            QTest::newRow(v) << QByteArray(v);
    }

    void runtimeAndHomeDirectoriesArePrivate()
    {
        QFETCH(QByteArray, var);
        const QString dir = qEnvironmentVariable(var.constData());
        QVERIFY2(dir.startsWith(c7::testing::hostIsolationRoot() + QLatin1Char('/')),
                 qPrintable(QStringLiteral("%1=%2").arg(QString::fromLatin1(var), dir)));
        QVERIFY(QFileInfo(dir).isDir());
        QVERIFY(QFileInfo(dir).isWritable());
    }

    void theRootIsAFreshTemporaryDirectory()
    {
        const QString root = c7::testing::hostIsolationRoot();
        QVERIFY(root.startsWith(QDir::tempPath() + QLatin1Char('/')));
        QCOMPARE(QFileInfo(root).permissions() & (QFile::ReadGroup | QFile::ReadOther), QFile::Permissions{});
    }

    void theHostDesktopIsUnset_data()
    {
        QTest::addColumn<QByteArray>("var");
        for (const char *v : {"HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY",
                              "DBUS_STARTER_ADDRESS"})
            QTest::newRow(v) << QByteArray(v);
    }

    void theHostDesktopIsUnset()
    {
        QFETCH(QByteArray, var);
        QVERIFY2(!qEnvironmentVariableIsSet(var.constData()), var.constData());
    }

    void aPrivateBusStillWorks()
    {
        c7::testing::PrivateBus bus;
        QVERIFY2(bus.isRunning(), qPrintable(bus.error()));
        QVERIFY(bus.connect().isConnected());
    }
};

C7_TEST_MAIN(TestIsolation)
#include "tst_isolation.moc"
