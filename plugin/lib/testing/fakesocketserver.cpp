#include "testing/fakesocketserver.h"

#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtNetwork/QLocalSocket>

namespace c7::testing {

FakeSocketServer::FakeSocketServer(const QString &path, QObject *parent)
    : QObject(parent), m_path(path)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        m_error = QStringLiteral("cannot create the directory for %1").arg(path);
        return;
    }
    // A full path, so QLocalServer neither prefixes a directory nor removes an
    // existing server's socket behind our back.
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server.listen(path)) {
        m_error = m_server.errorString();
        return;
    }
    connect(&m_server, &QLocalServer::newConnection, this, &FakeSocketServer::accept);
}

FakeSocketServer::~FakeSocketServer()
{
    // abort() emits disconnected() synchronously, and its handler edits
    // m_clients: take the list first and drop the handlers before aborting.
    const QList<QPointer<QLocalSocket>> clients = std::exchange(m_clients, {});
    for (const QPointer<QLocalSocket> &c : clients) {
        if (!c)
            continue;
        c->disconnect(this);
        c->abort();
    }
    m_server.close();
}

void FakeSocketServer::onRequest(Handler handler, AfterReply after)
{
    m_handler = std::move(handler);
    m_after = after;
}

void FakeSocketServer::pushLine(const QByteArray &line)
{
    // A copy: a write that fails can disconnect a client, which edits m_clients.
    const QList<QPointer<QLocalSocket>> clients = m_clients;
    for (const QPointer<QLocalSocket> &c : clients) {
        if (c && c->state() == QLocalSocket::ConnectedState)
            c->write(line + '\n');
    }
}

void FakeSocketServer::accept()
{
    while (QLocalSocket *client = m_server.nextPendingConnection()) {
        m_clients << client;
        connect(client, &QLocalSocket::readyRead, this, [this, client] { read(client); });
        connect(client, &QLocalSocket::disconnected, this, [this, client] {
            m_clients.removeAll(client);
            client->deleteLater();
        });
    }
}

void FakeSocketServer::read(QLocalSocket *client)
{
    const QByteArray request = client->readAll();
    if (request.isEmpty())
        return;
    m_requests << request;
    if (!m_handler)
        return;
    client->write(m_handler(request));
    if (m_after == CloseAfterReply)
        client->disconnectFromServer();
}

} // namespace c7::testing
