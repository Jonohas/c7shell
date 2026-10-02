#include "testing/fakeprogram.h"
#include "testing/testmain.h"
#include "testing/wait.h"

#include <QtCore/QFileInfo>
#include <QtCore/QProcess>
#include <QtTest/QTest>

using c7::testing::FakeProgram;
using c7::testing::waitUntil;

namespace {

// How a library under test runs a program: async QProcess, no waitFor*.
struct Run {
    QByteArray out;
    QByteArray err;
    int exitCode = -1;
};

Run run(QProcess &proc, const QString &program, const QStringList &args,
        const QByteArray &input = {})
{
    proc.start(program, args);
    waitUntil([&] { return proc.state() == QProcess::Running || proc.state() == QProcess::NotRunning; });
    if (!input.isNull()) {
        proc.write(input);
        proc.closeWriteChannel();
    }
    waitUntil([&] { return proc.state() == QProcess::NotRunning; });
    return {proc.readAllStandardOutput(), proc.readAllStandardError(), proc.exitCode()};
}

Run run(const QString &program, const QStringList &args, const QByteArray &input = {})
{
    QProcess proc;
    return run(proc, program, args, input);
}

} // namespace

class TestFakeProgram : public QObject {
    Q_OBJECT

private slots:
    void isNamedLikeTheProgramItStandsIn()
    {
        FakeProgram nmcli(QStringLiteral("nmcli"));
        QCOMPARE(QFileInfo(nmcli.path()).fileName(), QStringLiteral("nmcli"));
        QVERIFY(QFileInfo(nmcli.path()).isExecutable());
    }

    void recordsArgvAndPlaysBackTheReply()
    {
        FakeProgram nmcli(QStringLiteral("nmcli"));
        nmcli.reply("enabled\n", "warning\n", 3);
        const Run r = run(nmcli.path(), {QStringLiteral("radio"), QStringLiteral("wifi")});
        QCOMPARE(r.out, QByteArray("enabled\n"));
        QCOMPARE(r.err, QByteArray("warning\n"));
        QCOMPARE(r.exitCode, 3);
        QCOMPARE(nmcli.calls(), (QList<QStringList>{{QStringLiteral("radio"), QStringLiteral("wifi")}}));
    }

    void keepsArgumentsExactly()
    {
        FakeProgram p(QStringLiteral("grim"));
        p.reply({});
        const QStringList args{QStringLiteral("-g"), QStringLiteral("10,20 30x40"),
                               QString(), QStringLiteral("ünï\tcode")};
        run(p.path(), args);
        QCOMPARE(p.calls(), QList<QStringList>{args});
    }

    void repliesInTheOrderTheyWereScripted()
    {
        FakeProgram p(QStringLiteral("hyprctl"));
        p.reply("first");
        p.reply("second", {}, 1);
        QCOMPARE(run(p.path(), {QStringLiteral("a")}).out, QByteArray("first"));
        const Run second = run(p.path(), {QStringLiteral("b")});
        QCOMPARE(second.out, QByteArray("second"));
        QCOMPARE(second.exitCode, 1);
        QCOMPARE(p.calls().size(), 2);
    }

    void failsACallNobodyScripted()
    {
        FakeProgram p(QStringLiteral("rfkill"));
        const Run r = run(p.path(), {QStringLiteral("list")});
        QCOMPARE(r.exitCode, 127);
        QVERIFY(r.err.contains("no reply scripted for call 1"));
        QCOMPARE(p.calls().size(), 1);
    }

    void capturesStandardInputWhenAsked()
    {
        FakeProgram p(QStringLiteral("nmcli"));
        p.readStdin(true);
        p.reply({});
        run(p.path(), {QStringLiteral("--ask")}, "s3cret\n");
        QCOMPARE(p.stdins(), QList<QByteArray>{"s3cret\n"});
    }

    void isFoundOnPath()
    {
        FakeProgram p(QStringLiteral("playerctl"));
        p.reply("Playing\n");
        QProcess proc;
        QProcessEnvironment env;
        env.insert(QStringLiteral("PATH"), p.binDir());
        proc.setProcessEnvironment(env);
        QCOMPARE(run(proc, QStringLiteral("playerctl"), {QStringLiteral("status")}).out,
                 QByteArray("Playing\n"));
        QCOMPARE(p.calls(), QList<QStringList>{{QStringLiteral("status")}});
    }

    void needsNoEnvironment()
    {
        FakeProgram p(QStringLiteral("wpctl"));
        p.reply("ok");
        QProcess proc;
        proc.setProcessEnvironment(QProcessEnvironment());
        QCOMPARE(run(proc, p.path(), {}).out, QByteArray("ok"));
        QCOMPARE(p.calls().size(), 1);
    }

    void twoFakesKeepSeparateRecords()
    {
        FakeProgram a(QStringLiteral("nmcli"));
        FakeProgram b(QStringLiteral("nmcli"));
        a.reply("a");
        b.reply("b");
        QCOMPARE(run(a.path(), {}).out, QByteArray("a"));
        QCOMPARE(run(b.path(), {}).out, QByteArray("b"));
        QCOMPARE(a.calls().size(), 1);
        QCOMPARE(b.calls().size(), 1);
    }
};

C7_TEST_MAIN(TestFakeProgram)
#include "tst_fakeprogram.moc"
