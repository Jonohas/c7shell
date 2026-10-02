#include "testing/testmain.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QTemporaryDir>

#include <cstdio>
#include <cstdlib>

namespace c7::testing {

namespace {

// Lives until the process exits, then takes the directory with it.
QTemporaryDir &root()
{
    static QTemporaryDir dir(QDir::tempPath() + QStringLiteral("/c7-test-XXXXXX"));
    return dir;
}

[[noreturn]] void refuse(const QString &why)
{
    // Running against the host instead is the one thing this must not do.
    std::fprintf(stderr, "c7 test: cannot isolate from the host: %s\n", qPrintable(why));
    std::exit(2);
}

} // namespace

void isolateFromHost()
{
    QTemporaryDir &dir = root();
    if (!dir.isValid())
        refuse(dir.errorString());
    const QString base = dir.path();

    const QByteArray dead = QStringLiteral("unix:path=%1/no-such-bus").arg(base).toLocal8Bit();
    qputenv("DBUS_SESSION_BUS_ADDRESS", dead);
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", dead);
    qunsetenv("DBUS_STARTER_ADDRESS");
    qunsetenv("DBUS_STARTER_BUS_TYPE");

    static const struct {
        const char *var;
        const char *sub;
    } dirs[] = {
        {"HOME", "home"},           {"XDG_RUNTIME_DIR", "runtime"}, {"XDG_CONFIG_HOME", "config"},
        {"XDG_DATA_HOME", "data"}, {"XDG_CACHE_HOME", "cache"},    {"XDG_STATE_HOME", "state"},
    };
    for (const auto &d : dirs) {
        const QString path = base + QLatin1Char('/') + QLatin1String(d.sub);
        if (!QDir().mkpath(path))
            refuse(QStringLiteral("cannot create %1").arg(path));
        qputenv(d.var, path.toLocal8Bit());
    }
    // Qt warns about, and some programs refuse, a runtime directory others can read.
    if (!QFile::setPermissions(base + QStringLiteral("/runtime"),
                               QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner))
        refuse(QStringLiteral("cannot make the runtime directory private"));

    for (const char *v : {"HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY"})
        qunsetenv(v);
}

QString hostIsolationRoot()
{
    return root().path();
}

} // namespace c7::testing
