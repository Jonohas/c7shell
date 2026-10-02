#include "testing/privatebus.h"
#include "testing/testmain.h"

#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusConnectionInterface>
#include <QtTest/QTest>

using c7::testing::PrivateBus;

class TestPrivateBus : public QObject {
    Q_OBJECT

private slots:
    void startsAndHandsOutConnections()
    {
        PrivateBus bus;
        QVERIFY2(bus.isRunning(), qPrintable(bus.error()));
        QVERIFY(bus.address().startsWith(QLatin1String("unix:")));
        QDBusConnection c = bus.connect();
        QVERIFY2(c.isConnected(), qPrintable(c.lastError().message()));
        QVERIFY(!c.baseService().isEmpty());
    }

    void eachConnectionIsItsOwnPeer()
    {
        PrivateBus bus;
        QVERIFY2(bus.isRunning(), qPrintable(bus.error()));
        QVERIFY(bus.connect().baseService() != bus.connect().baseService());
    }

    void twoBusesShareNothing()
    {
        PrivateBus a;
        PrivateBus b;
        QVERIFY2(a.isRunning() && b.isRunning(), qPrintable(a.error() + b.error()));
        QVERIFY(a.address() != b.address());

        const QString name = QStringLiteral("org.c7.Test.Shared");
        QDBusConnection ca = a.connect();
        QDBusConnection cb = b.connect();
        QVERIFY(ca.registerService(name));
        QVERIFY(ca.interface()->isServiceRegistered(name));
        QVERIFY(!cb.interface()->isServiceRegistered(name));
        // Free on b, so b can take it too.
        QVERIFY(cb.registerService(name));
    }

    void startsASystemBus()
    {
        PrivateBus bus(PrivateBus::Kind::System);
        QVERIFY2(bus.isRunning(), qPrintable(bus.error()));
        QVERIFY(bus.connect().isConnected());
    }

    void stopsWithTheFixture()
    {
        QString address;
        {
            PrivateBus bus;
            QVERIFY2(bus.isRunning(), qPrintable(bus.error()));
            address = bus.address();
        }
        QDBusConnection after = QDBusConnection::connectToBus(address, QStringLiteral("after"));
        const bool connected = after.isConnected();
        QDBusConnection::disconnectFromBus(QStringLiteral("after"));
        QVERIFY(!connected);
    }

    void reportsADaemonThatWillNotStart()
    {
        PrivateBus bus(PrivateBus::Kind::Session, QStringLiteral("/nonexistent/dbus-daemon"));
        QVERIFY(!bus.isRunning());
        QVERIFY(!bus.error().isEmpty());
        QVERIFY(!bus.connect().isConnected());
    }
};

C7_TEST_MAIN(TestPrivateBus)
#include "tst_privatebus.moc"
