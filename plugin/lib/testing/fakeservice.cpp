#include "testing/fakeservice.h"

#include <QtCore/QMetaProperty>
#include <QtDBus/QDBusConnectionInterface>
#include <QtDBus/QDBusMessage>

namespace c7::testing {

FakeService::FakeService(QDBusConnection bus, const QString &name)
    : m_bus(std::move(bus)), m_name(name)
{
    // registerService() reports success when the name is already queued for us,
    // so ask the bus for the outcome directly: we are the primary owner or not.
    QDBusConnectionInterface *iface = m_bus.interface();
    if (!iface)
        return;
    const QDBusReply<QDBusConnectionInterface::RegisterServiceReply> reply =
        iface->registerService(name, QDBusConnectionInterface::DontQueueService,
                               QDBusConnectionInterface::DontAllowReplacement);
    m_ownsName = reply.isValid() && reply.value() == QDBusConnectionInterface::ServiceRegistered;
}

FakeService::~FakeService()
{
    for (auto it = m_objects.cbegin(); it != m_objects.cend(); ++it)
        m_bus.unregisterObject(it.key());
    if (m_ownsName)
        m_bus.unregisterService(m_name);
}

bool FakeService::exportObject(const QString &path, QObject *object)
{
    if (!object || m_objects.contains(path))
        return false;
    const QMetaObject *meta = object->metaObject();
    const int info = meta->indexOfClassInfo("D-Bus Interface");
    if (info < 0)
        return false;
    const QString interface = QString::fromLatin1(meta->classInfo(info).value());
    if (!m_bus.registerObject(path, object,
                              QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals
                                  | QDBusConnection::ExportAllProperties))
        return false;
    m_objects.insert(path, {object, interface});
    return true;
}

bool FakeService::setProperty(const QString &path, const QString &property, const QVariant &value)
{
    const auto it = m_objects.constFind(path);
    if (it == m_objects.cend() || !it->object)
        return false;
    QObject *object = it->object;
    const QByteArray name = property.toUtf8();
    if (object->metaObject()->indexOfProperty(name.constData()) < 0
        || !object->setProperty(name.constData(), value))
        return false;

    QDBusMessage changed = QDBusMessage::createSignal(
        path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
    changed << it->interface << QVariantMap{{property, object->property(name.constData())}}
            << QStringList();
    return m_bus.send(changed);
}

bool FakeService::emitSignal(const QString &path, const QString &signal, const QVariantList &args)
{
    const auto it = m_objects.constFind(path);
    if (it == m_objects.cend())
        return false;
    QDBusMessage message = QDBusMessage::createSignal(path, it->interface, signal);
    message.setArguments(args);
    return m_bus.send(message);
}

} // namespace c7::testing
