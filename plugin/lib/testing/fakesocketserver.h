#pragma once

#include <QtCore/QByteArrayList>
#include <QtCore/QList>
#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtNetwork/QLocalServer>

#include <functional>

class QLocalSocket;

namespace c7::testing {

// A Unix socket server at a path the test chooses, standing in for one a
// program c7shell talks to: Hyprland's request socket (write a command, read
// the reply, the server closes) and its event socket (the server pushes lines),
// hyprsunset's, hyprpaper's. Removed when the fixture goes.
//
// A request is what one client sends in one write, as those servers read it.
class FakeSocketServer : public QObject {
    Q_OBJECT

public:
    using Handler = std::function<QByteArray(const QByteArray &request)>;
    enum AfterReply { CloseAfterReply, KeepOpen };

    explicit FakeSocketServer(const QString &path, QObject *parent = nullptr);
    ~FakeSocketServer() override;

    bool isListening() const { return m_server.isListening(); }
    QString error() const { return m_error; }
    QString path() const { return m_path; }

    // Answer every request with `handler`'s reply; by default close the client
    // after it. Without a handler a request is recorded and left unanswered.
    void onRequest(Handler handler, AfterReply after = CloseAfterReply);

    // Send `line` and a newline to every connected client.
    void pushLine(const QByteArray &line);

    // Every request received, in order.
    QByteArrayList requests() const { return m_requests; }
    int clientCount() const { return m_clients.size(); }

private:
    void accept();
    void read(QLocalSocket *client);

    QLocalServer m_server;
    QString m_path;
    QString m_error;
    Handler m_handler;
    AfterReply m_after = CloseAfterReply;
    QByteArrayList m_requests;
    QList<QPointer<QLocalSocket>> m_clients;
};

} // namespace c7::testing
