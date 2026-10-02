#pragma once

#include <QtCore/QHash>
#include <QtCore/QPointer>
#include <QtCore/QVariantList>
#include <QtDBus/QDBusConnection>

namespace c7::testing {

// A D-Bus service a test writes in C++: it owns `name` on `bus` (usually a
// PrivateBus connection) and exports test-defined QObjects. An exported
// object's interface name is its Q_CLASSINFO("D-Bus Interface", ...): its
// slots answer method calls, its signals go out as D-Bus signals and its
// properties answer org.freedesktop.DBus.Properties.Get, GetAll and Set.
//
// Qt does not announce a property change on its own; setProperty() changes the
// property and emits PropertiesChanged, as a real service would.
class FakeService {
public:
    FakeService(QDBusConnection bus, const QString &name);
    ~FakeService();

    FakeService(const FakeService &) = delete;
    FakeService &operator=(const FakeService &) = delete;

    // The name was free on the bus and is now ours.
    bool ownsName() const { return m_ownsName; }

    // Export `object` at `path`. The test keeps ownership. Refuses an object
    // with no D-Bus Interface class info (Qt would export it under a made-up
    // name no client asks for) and a path already exported.
    bool exportObject(const QString &path, QObject *object);

    // Set `property` on the object at `path` and emit PropertiesChanged for it.
    // Refuses a path nobody exported and a property the object does not declare.
    bool setProperty(const QString &path, const QString &property, const QVariant &value);

    // Emit `signal` from `path` with `args`, without the object declaring it.
    bool emitSignal(const QString &path, const QString &signal, const QVariantList &args);

private:
    struct Exported {
        QPointer<QObject> object;
        QString interface;
    };

    QDBusConnection m_bus;
    QString m_name;
    bool m_ownsName = false;
    QHash<QString, Exported> m_objects;
};

} // namespace c7::testing
