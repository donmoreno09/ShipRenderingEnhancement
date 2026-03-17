#ifndef IPERSISTABLE_H
#define IPERSISTABLE_H

#include <QJsonObject>

class IPersistable
{
public:
    virtual ~IPersistable() = default;
    virtual QJsonObject toJson() const = 0;
    virtual void fromJson(const QJsonObject &json) = 0;
};

#endif // IPERSISTABLE_H
