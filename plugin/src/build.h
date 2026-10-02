#pragma once

#include "core/version.h"

#include <QObject>
#include <QtQml/qqmlregistration.h>

// C7.Build: the version of the C7 plugin the shell loaded.
class Build : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit Build(QObject *parent = nullptr) : QObject(parent) {}

    QString version() const { return c7::core::version(); }
};
