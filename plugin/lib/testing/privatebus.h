#pragma once

#include <QtCore/QProcess>
#include <QtCore/QStringList>
#include <QtCore/QTemporaryDir>
#include <QtDBus/QDBusConnection>

namespace c7::testing {

// A dbus-daemon of the test's own, started in the constructor and stopped in
// the destructor. It has no service directories, so a call to a name nobody
// owns fails instead of activating a real service, and it listens in a
// directory of its own, so two buses side by side share nothing.
//
// A library under test takes its QDBusConnection from connect(); it never
// reaches for QDBusConnection::sessionBus() or systemBus().
class PrivateBus {
public:
    enum class Kind { Session, System };

    explicit PrivateBus(Kind kind = Kind::Session,
                        const QString &daemon = QStringLiteral("dbus-daemon"));
    ~PrivateBus();

    PrivateBus(const PrivateBus &) = delete;
    PrivateBus &operator=(const PrivateBus &) = delete;

    // The daemon started and printed its address.
    bool isRunning() const { return !m_address.isEmpty(); }
    // Why it is not running; empty when it is.
    QString error() const { return m_error; }
    QString address() const { return m_address; }

    // A new connection to this bus, with a unique name of its own. Disconnected
    // when the bus is not running, and once the fixture is gone.
    QDBusConnection connect();

private:
    void start(Kind kind, const QString &daemon);

    QTemporaryDir m_dir;
    QProcess m_daemon;
    QString m_address;
    QString m_error;
    QStringList m_connections;
};

} // namespace c7::testing
