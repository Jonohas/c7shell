#pragma once

#include <QtCore/QByteArrayList>
#include <QtCore/QList>
#include <QtCore/QStringList>
#include <QtCore/QTemporaryDir>

namespace c7::testing {

// The files FakeProgram and c7-fake-program share, under <dir>/state:
//   replies/<n>/{out,err,code}   the reply to run n, counted from 1
//   calls/<n>.json               run n: {"argv": [...], "stdin": base64}
//   read-stdin                   present: every run reads stdin to its end
//   lock                         serialises runs that start together
// c7-fake-program finds <dir> from its own path, <dir>/bin/<name>, so it needs
// no environment.
namespace fakeprogram {
inline constexpr char kReplies[] = "replies";
inline constexpr char kCalls[] = "calls";
inline constexpr char kReadStdin[] = "read-stdin";
inline constexpr char kLock[] = "lock";
inline constexpr char kOut[] = "out";
inline constexpr char kErr[] = "err";
inline constexpr char kCode[] = "code";
inline constexpr int kUnscripted = 127;
} // namespace fakeprogram

// A program a library under test runs, in place of the real one (nmcli, grim,
// hyprctl). path() is an executable named like that program; hand it to the
// library, or put binDir() first on its PATH. Each run records its argv (and,
// if asked, its standard input) and plays back the next scripted reply. The
// library's own QProcess code runs unchanged.
//
// A run nobody scripted a reply for exits 127 and says so on stderr, so a test
// that forgot one fails instead of passing on an empty answer.
class FakeProgram {
public:
    explicit FakeProgram(const QString &name);

    FakeProgram(const FakeProgram &) = delete;
    FakeProgram &operator=(const FakeProgram &) = delete;

    // The fake exists and every reply so far was written. A test asserts this
    // when a fixture problem would otherwise look like a library bug.
    bool isValid() const { return m_error.isEmpty(); }
    QString error() const { return m_error; }

    QString path() const;
    QString binDir() const;

    // The reply to the next run that has none yet: stdout, stderr, exit code.
    void reply(const QByteArray &out, const QByteArray &err = {}, int exitCode = 0);
    // Read standard input to its end on every run and record it.
    void readStdin(bool on);

    // The arguments of each run, without argv[0], in the order they ran.
    QList<QStringList> calls() const;
    // What each run read on standard input; empty entries unless readStdin(true).
    QByteArrayList stdins() const;

private:
    QString state(const QString &rel = {}) const;
    void fail(const QString &why);

    QTemporaryDir m_dir;
    QString m_name;
    QString m_error;
    int m_replies = 0;
};

} // namespace c7::testing
