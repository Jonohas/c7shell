#include "testing/fakeservice.h"
#include "testing/privatebus.h"
#include "testing/testmain.h"
#include "testing/wait.h"

#include <QtDBus/QDBusConnectionInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusVariant>
#include <QtTest/QTest>

using c7::testing::FakeService;
using c7::testing::PrivateBus;
using c7::testing::waitUntil;

namespace {

const QString kName = QStringLiteral("org.c7.Test");
const QString kPath = QStringLiteral("/thing");
const QString kIface = QStringLiteral("org.c7.Test.Thing");

// What a test defines: the service's methods are its slots, its signals are
// its signals, and its properties are its properties.
class Thing : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state WRITE setState)

public:
    QString state() const { return m_state; }
    void setState(const QString &s) { m_state = s; }

public slots:
    QString Echo(const QString &text) { return text; }

signals:
    void Ping(const QString &what);

private:
    QString m_state = QStringLiteral("idle");
};

// The client side: records every signal it is connected to.
class Listener : public QObject {
    Q_OBJECT

public:
    QStringList pings;
    QVariantMap changed;

public slots:
    void onPing(const QString &what) { pings << what; }
    void onPropertiesChanged(const QString &, const QVariantMap &props, const QStringList &)
    {
        changed.insert(props);
    }
};

} // namespace

class TestFakeService : public QObject {
    Q_OBJECT

private slots:
    void init()
    {
        bus = std::make_unique<PrivateBus>();
        QVERIFY2(bus->isRunning(), qPrintable(bus->error()));
        service = std::make_unique<FakeService>(bus->connect(), kName);
        QVERIFY(service->ownsName());
        QVERIFY(service->exportObject(kPath, &thing, kIface));
        client = bus->connect();
    }

    void cleanup()
    {
        service.reset();
        bus.reset();
    }

    void ownsItsName() { QVERIFY(client.interface()->isServiceRegistered(kName)); }

    void aSecondOwnerIsRefused()
    {
        FakeService second(bus->connect(), kName);
        QVERIFY(!second.ownsName());
    }

    void answersMethods()
    {
        QDBusMessage call = QDBusMessage::createMethodCall(kName, kPath, kIface, QStringLiteral("Echo"));
        call << QStringLiteral("hi");
        QDBusPendingReply<QString> reply = client.asyncCall(call);
        QVERIFY(waitUntil([&] { return reply.isFinished(); }));
        QVERIFY2(reply.isValid(), qPrintable(reply.error().message()));
        QCOMPARE(reply.value(), QStringLiteral("hi"));
    }

    void servesProperties()
    {
        QDBusMessage get = QDBusMessage::createMethodCall(
            kName, kPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        get << kIface << QStringLiteral("state");
        QDBusPendingReply<QDBusVariant> reply = client.asyncCall(get);
        QVERIFY(waitUntil([&] { return reply.isFinished(); }));
        QVERIFY2(reply.isValid(), qPrintable(reply.error().message()));
        QCOMPARE(reply.value().variant().toString(), QStringLiteral("idle"));
    }

    void emitsTheObjectsSignals()
    {
        Listener listener;
        QVERIFY(client.connect(kName, kPath, kIface, QStringLiteral("Ping"), &listener,
                               SLOT(onPing(QString))));
        emit thing.Ping(QStringLiteral("from-qt"));
        QVERIFY(waitUntil([&] { return !listener.pings.isEmpty(); }));
        QCOMPARE(listener.pings, QStringList{QStringLiteral("from-qt")});
    }

    void emitsAdHocSignals()
    {
        Listener listener;
        QVERIFY(client.connect(kName, kPath, kIface, QStringLiteral("Ping"), &listener,
                               SLOT(onPing(QString))));
        QVERIFY(service->emitSignal(kPath, QStringLiteral("Ping"), {QStringLiteral("ad-hoc")}));
        QVERIFY(waitUntil([&] { return !listener.pings.isEmpty(); }));
        QCOMPARE(listener.pings, QStringList{QStringLiteral("ad-hoc")});
    }

    void setPropertyChangesItAndNotifies()
    {
        Listener listener;
        QVERIFY(client.connect(kName, kPath, QStringLiteral("org.freedesktop.DBus.Properties"),
                               QStringLiteral("PropertiesChanged"), &listener,
                               SLOT(onPropertiesChanged(QString, QVariantMap, QStringList))));
        QVERIFY(service->setProperty(kPath, QStringLiteral("state"), QStringLiteral("busy")));
        QCOMPARE(thing.state(), QStringLiteral("busy"));
        QVERIFY(waitUntil([&] { return listener.changed.contains(QStringLiteral("state")); }));
        QCOMPARE(listener.changed.value(QStringLiteral("state")).toString(), QStringLiteral("busy"));
    }

    void refusesAnUnexportedPath()
    {
        QVERIFY(!service->setProperty(QStringLiteral("/nope"), QStringLiteral("state"), 1));
        QVERIFY(!service->emitSignal(QStringLiteral("/nope"), QStringLiteral("Ping"), {}));
    }

    void refusesAnUnknownProperty()
    {
        QVERIFY(!service->setProperty(kPath, QStringLiteral("noSuchProperty"), 1));
    }

private:
    std::unique_ptr<PrivateBus> bus;
    std::unique_ptr<FakeService> service;
    QDBusConnection client{QString()};
    Thing thing;
};

C7_TEST_MAIN(TestFakeService)
#include "tst_fakeservice.moc"
