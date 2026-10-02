#include "version.h"

#include <QtQml/QQmlEngine>
#include <QtTest/QTest>

// `import C7` resolves from the built module directory alone, the way the
// shell finds the installed one. C7_QML_IMPORT_PATH is that directory, and it
// is the only import path, so an installed copy of C7 cannot stand in for it.
class TestModule : public QObject {
    Q_OBJECT

private slots:
    void buildSingletonReportsTheLibraryVersion()
    {
        QQmlEngine engine;
        engine.setImportPathList({QStringLiteral(C7_QML_IMPORT_PATH)});
        auto *build = engine.singletonInstance<QObject *>("C7", "Build");
        QVERIFY2(build, "the C7 module or its Build singleton did not load");
        QCOMPARE(build->property("version").toString(), c7::core::version());
    }
};

QTEST_GUILESS_MAIN(TestModule)
#include "tst_module.moc"
