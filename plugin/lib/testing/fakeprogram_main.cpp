// c7-fake-program: what a FakeProgram puts on disk as <dir>/bin/<name>. Records
// the run and plays back the scripted reply; see fakeprogram.h for the files.
#include "testing/fakeprogram.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QLockFile>
#include <QtCore/QStandardPaths>

#include <cstdio>

namespace fp = c7::testing::fakeprogram;

namespace {

int die(int code, const QString &why)
{
    std::fprintf(stderr, "c7-fake-program: %s\n", qPrintable(why));
    return code;
}

// <dir>/state, from the path this run was started as. Started by bare name, it
// was found on PATH; the link's directory, not its target's, is the one we want.
QString stateDir(const QString &argv0)
{
    const QString self = argv0.contains(QLatin1Char('/')) ? argv0
                                                          : QStandardPaths::findExecutable(argv0);
    if (self.isEmpty())
        return {};
    return QFileInfo(self).absoluteDir().absoluteFilePath(QStringLiteral("../state"));
}

QByteArray readAll(const QString &path, bool *ok)
{
    QFile f(path);
    *ok = f.open(QIODevice::ReadOnly);
    return *ok ? f.readAll() : QByteArray();
}

bool writeAll(FILE *to, const QByteArray &data)
{
    return std::fwrite(data.constData(), 1, size_t(data.size()), to) == size_t(data.size())
           && std::fflush(to) == 0;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QStringList args = app.arguments();
    const QString state = stateDir(args.takeFirst());
    if (state.isEmpty() || !QFileInfo(state).isDir())
        return die(126, QStringLiteral("cannot find my state directory (run as %1)")
                            .arg(QString::fromLocal8Bit(argv[0])));

    QByteArray input;
    if (QFileInfo::exists(state + QLatin1Char('/') + QLatin1String(fp::kReadStdin))) {
        QFile in;
        if (!in.open(stdin, QIODevice::ReadOnly))
            return die(126, QStringLiteral("cannot read standard input"));
        input = in.readAll();
    }

    // Take the next run number and record the run under the lock, so two runs
    // started together never share one.
    QLockFile lock(state + QLatin1Char('/') + QLatin1String(fp::kLock));
    if (!lock.lock())
        return die(126, QStringLiteral("cannot take %1").arg(lock.fileName()));
    const QString calls = state + QLatin1Char('/') + QLatin1String(fp::kCalls);
    int n = 1;
    while (QFileInfo::exists(QStringLiteral("%1/%2.json").arg(calls).arg(n)))
        ++n;
    QFile record(QStringLiteral("%1/%2.json").arg(calls).arg(n));
    const QJsonObject run{{QStringLiteral("argv"), QJsonArray::fromStringList(args)},
                          {QStringLiteral("stdin"), QString::fromLatin1(input.toBase64())}};
    const QByteArray json = QJsonDocument(run).toJson(QJsonDocument::Compact);
    if (!record.open(QIODevice::WriteOnly) || record.write(json) != json.size())
        return die(126, QStringLiteral("cannot record the run in %1").arg(record.fileName()));
    record.close();
    lock.unlock();

    const QString reply = QStringLiteral("%1/%2/%3").arg(state, QLatin1String(fp::kReplies)).arg(n);
    bool ok = false;
    const QByteArray code = readAll(reply + QLatin1Char('/') + QLatin1String(fp::kCode), &ok);
    if (!ok)
        return die(fp::kUnscripted, QStringLiteral("no reply scripted for call %1").arg(n));
    bool okOut = false;
    bool okErr = false;
    const QByteArray out = readAll(reply + QLatin1Char('/') + QLatin1String(fp::kOut), &okOut);
    const QByteArray err = readAll(reply + QLatin1Char('/') + QLatin1String(fp::kErr), &okErr);
    if (!okOut || !okErr)
        return die(126, QStringLiteral("reply %1 is incomplete").arg(n));
    if (!writeAll(stdout, out) || !writeAll(stderr, err))
        return 126;
    return code.toInt();
}
