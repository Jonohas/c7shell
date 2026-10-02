#include "testing/fakesocketserver.h"
#include "testing/testmain.h"
#include "testing/wait.h"

#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>
#include <QtNetwork/QLocalSocket>
#include <QtTest/QTest>

using c7::testing::FakeSocketServer;
using c7::testing::waitUntil;

namespace {

// A client the way a library under test would be one: connect, write, read.
std::unique_ptr<QLocalSocket> connectTo(const QString &path)
{
    auto s = std::make_unique<QLocalSocket>();
    s->connectToServer(path);
    waitUntil([&] { return s->state() == QLocalSocket::ConnectedState; });
    return s;
}

} // namespace

class TestFakeSocketServer : public QObject {
    Q_OBJECT

private slots:
    void init()
    {
        QVERIFY(dir.isValid());
        // Nested, as Hyprland's are: $XDG_RUNTIME_DIR/hypr/<signature>/.socket.sock
        path = dir.filePath(QStringLiteral("hypr/sig/.socket.sock"));
    }

    void listensAtTheGivenPath()
    {
        FakeSocketServer server(path);
        QVERIFY2(server.isListening(), qPrintable(server.error()));
        QCOMPARE(server.path(), path);
        QVERIFY(QFileInfo::exists(path));
    }

    void repliesAndClosesLikeARequestSocket()
    {
        FakeSocketServer server(path);
        server.onRequest([](const QByteArray &req) { return "ok:" + req; });
        auto client = connectTo(path);
        QCOMPARE(client->state(), QLocalSocket::ConnectedState);
        client->write("dispatch workspace 2");

        QByteArray got;
        QVERIFY(waitUntil([&] {
            got += client->readAll();
            return client->state() == QLocalSocket::UnconnectedState;
        }));
        got += client->readAll();
        QCOMPARE(got, QByteArray("ok:dispatch workspace 2"));
        QCOMPARE(server.requests(), QList<QByteArray>{"dispatch workspace 2"});
    }

    void canKeepTheClientOpen()
    {
        FakeSocketServer server(path);
        server.onRequest([](const QByteArray &) { return QByteArray("pong"); },
                         FakeSocketServer::KeepOpen);
        auto client = connectTo(path);
        client->write("ping");
        QByteArray got;
        QVERIFY(waitUntil([&] { return (got += client->readAll()) == "pong"; }));
        client->write("ping");
        got.clear();
        QVERIFY(waitUntil([&] { return (got += client->readAll()) == "pong"; }));
        QCOMPARE(client->state(), QLocalSocket::ConnectedState);
        QCOMPARE(server.requests().size(), 2);
    }

    void pushesLinesToEveryClientLikeAnEventSocket()
    {
        FakeSocketServer server(path);
        auto first = connectTo(path);
        auto second = connectTo(path);
        QVERIFY(waitUntil([&] { return server.clientCount() == 2; }));

        server.pushLine("workspace>>2");
        QByteArray a;
        QByteArray b;
        QVERIFY(waitUntil([&] {
            a += first->readAll();
            b += second->readAll();
            return a.endsWith('\n') && b.endsWith('\n');
        }));
        QCOMPARE(a, QByteArray("workspace>>2\n"));
        QCOMPARE(b, QByteArray("workspace>>2\n"));
    }

    void recordsRequestsWithoutAHandler()
    {
        FakeSocketServer server(path);
        auto client = connectTo(path);
        client->write("j/clients");
        QVERIFY(waitUntil([&] { return !server.requests().isEmpty(); }));
        QCOMPARE(server.requests().first(), QByteArray("j/clients"));
        QCOMPARE(client->state(), QLocalSocket::ConnectedState);
    }

    void removesTheSocketWhenDestroyed()
    {
        {
            FakeSocketServer server(path);
            QVERIFY(server.isListening());
        }
        QVERIFY(!QFileInfo::exists(path));
    }

    void reportsAPathItCannotListenOn()
    {
        FakeSocketServer server(QStringLiteral("/proc/c7-no-such-dir/.socket.sock"));
        QVERIFY(!server.isListening());
        QVERIFY(!server.error().isEmpty());
    }

private:
    QTemporaryDir dir;
    QString path;
};

C7_TEST_MAIN(TestFakeSocketServer)
#include "tst_fakesocketserver.moc"
