#include "core/version.h"

#include <QtCore/QFileInfo>
#include <QtQml/QQmlEngine>
#include <QtTest/QTest>

// `import C7` resolves from the built module directory alone, the way the
// shell finds the installed one. C7_QML_IMPORT_PATH is that directory, and it
// is the only import path, so an installed copy of C7 cannot stand in for it.
// That also rules out `import QtQml`, so the test reads the singleton from C++
// rather than through a QML document.
class TestModule : public QObject {
    Q_OBJECT

private slots:
    void buildSingletonReportsTheLibraryVersion()
    {
        const QString importPath = QStringLiteral(C7_QML_IMPORT_PATH);
        QQmlEngine engine;
        engine.setImportPathList({importPath});
        auto *build = engine.singletonInstance<QObject *>("C7", "Build");
        // Qt reports nothing here, so say which half is broken: the module
        // directory, or loading the plugin and its Build singleton from it.
        QVERIFY2(build, QFileInfo::exists(importPath + QStringLiteral("/C7/qmldir"))
                            ? "C7/qmldir exists, but its plugin or Build singleton did not load"
                            : "module C7 is not installed: no C7/qmldir under the import path");
        QCOMPARE(build->property("version").toString(), c7::core::version());
    }
};

QTEST_GUILESS_MAIN(TestModule)
#include "tst_module.moc"
