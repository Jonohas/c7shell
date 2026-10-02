#include "testing/testmain.h"
#include "testing/wait.h"

#include <QtCore/QTimer>
#include <QtTest/QTest>

using c7::testing::waitUntil;

class TestWait : public QObject {
    Q_OBJECT

private slots:
    void returnsAtOnceWhenAlreadyTrue() { QVERIFY(waitUntil([] { return true; })); }

    void runsTheEventLoopUntilTheConditionHolds()
    {
        bool fired = false;
        QTimer::singleShot(0, this, [&] { fired = true; });
        QVERIFY(waitUntil([&] { return fired; }));
    }

    void givesUpAtTheBound()
    {
        // The bound is an upper limit, never a delay a passing test waits out.
        QVERIFY(!waitUntil([] { return false; }, std::chrono::milliseconds(20)));
    }

    void theDefaultBoundIsGenerous()
    {
        QVERIFY(c7::testing::kWaitBound >= std::chrono::seconds(10));
    }
};

C7_TEST_MAIN(TestWait)
#include "tst_wait.moc"
