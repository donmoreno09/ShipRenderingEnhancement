#pragma once

#include <QNetworkReply>
#include <QPointer>
#include <QString>
#include <functional>

struct ErrorResult {
    int status = 0;
    QString message;
    QPointer<QNetworkReply> reply;
};

using ErrorCb = std::function<void(const ErrorResult&)>;
