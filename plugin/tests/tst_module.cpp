#include "core/version.h"

#include <QtQml/QQmlComponent>
#include <QtQml/QQmlEngine>
#include <QtTest/QTest>

#include <memory>

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
        QQmlComponent component(&engine);
        component.setData("import QtQml\nimport C7\nQtObject { property string v: Build.version }",
                          QUrl(QStringLiteral("inline:tst_module.qml")));
        std::unique_ptr<QObject> object(component.create());
        // The error names the cause: a missing module, an unloadable plugin, a
        // renamed singleton.
        QVERIFY2(object, qPrintable(component.errorString()));
        QCOMPARE(object->property("v").toString(), c7::core::version());
    }
};

QTEST_GUILESS_MAIN(TestModule)
#include "tst_module.moc"
