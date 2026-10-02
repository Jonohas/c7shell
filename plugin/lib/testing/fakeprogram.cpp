#include "testing/fakeprogram.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>

namespace c7::testing {

namespace fp = fakeprogram;

namespace {

bool writeFile(const QString &path, const QByteArray &data)
{
    QFile f(path);
    return f.open(QIODevice::WriteOnly) && f.write(data) == data.size();
}

// Every recorded run, in order. Files are named by their run number.
QList<QJsonObject> runs(const QString &dir)
{
    QList<QJsonObject> out;
    for (int n = 1;; ++n) {
        QFile f(QStringLiteral("%1/%2.json").arg(dir).arg(n));
        if (!f.open(QIODevice::ReadOnly))
            return out;
        out << QJsonDocument::fromJson(f.readAll()).object();
    }
}

} // namespace

FakeProgram::FakeProgram(const QString &name) : m_name(name)
{
    if (!m_dir.isValid()) {
        fail(m_dir.errorString());
        return;
    }
    for (const char *sub : {"bin", "state/replies", "state/calls"}) {
        if (!QDir().mkpath(m_dir.filePath(QLatin1String(sub)))) {
            fail(QStringLiteral("cannot create %1").arg(QLatin1String(sub)));
            return;
        }
    }
    // A link, not a copy: c7-fake-program reads its directory from this path.
    if (!QFile::link(QStringLiteral(C7_FAKE_PROGRAM_BIN), path()))
        fail(QStringLiteral("cannot link %1 to %2").arg(path(), QStringLiteral(C7_FAKE_PROGRAM_BIN)));
}

QString FakeProgram::path() const
{
    return binDir() + QLatin1Char('/') + m_name;
}

QString FakeProgram::binDir() const
{
    return m_dir.filePath(QStringLiteral("bin"));
}

QString FakeProgram::state(const QString &rel) const
{
    return m_dir.filePath(rel.isEmpty() ? QStringLiteral("state") : QStringLiteral("state/") + rel);
}

void FakeProgram::fail(const QString &why)
{
    if (m_error.isEmpty())
        m_error = why;
}

void FakeProgram::reply(const QByteArray &out, const QByteArray &err, int exitCode)
{
    const QString dir = state(QStringLiteral("%1/%2").arg(QLatin1String(fp::kReplies)).arg(++m_replies));
    if (!QDir().mkpath(dir) || !writeFile(dir + QLatin1Char('/') + QLatin1String(fp::kOut), out)
        || !writeFile(dir + QLatin1Char('/') + QLatin1String(fp::kErr), err)
        || !writeFile(dir + QLatin1Char('/') + QLatin1String(fp::kCode), QByteArray::number(exitCode)))
        fail(QStringLiteral("cannot write reply %1 in %2").arg(m_replies).arg(dir));
}

void FakeProgram::readStdin(bool on)
{
    const QString flag = state(QLatin1String(fp::kReadStdin));
    if (on ? !writeFile(flag, {}) : (QFile::exists(flag) && !QFile::remove(flag)))
        fail(QStringLiteral("cannot set %1").arg(flag));
}

QList<QStringList> FakeProgram::calls() const
{
    QList<QStringList> out;
    for (const QJsonObject &run : runs(state(QLatin1String(fp::kCalls)))) {
        QStringList argv;
        for (const QJsonValue &a : run.value(QLatin1String("argv")).toArray())
            argv << a.toString();
        out << argv;
    }
    return out;
}

QByteArrayList FakeProgram::stdins() const
{
    QByteArrayList out;
    for (const QJsonObject &run : runs(state(QLatin1String(fp::kCalls))))
        out << QByteArray::fromBase64(run.value(QLatin1String("stdin")).toString().toLatin1());
    return out;
}

} // namespace c7::testing
