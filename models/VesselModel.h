#ifndef VESSELMODEL_H
#define VESSELMODEL_H

#include <QAbstractListModel>
#include <QVector>
#include <QQmlEngine>
#include "entities/Vessel.h"

class VesselApi;

// VesselModel
// QML-exposed singleton list model of AIS vessels.
// Loaded once at startup via fetch(). Read-only from QML.
//
// Roles exposed to QML delegates:
//   mmsi, name, lat, lon, displayHeading, speed,
//   a, b, c, d, shipLength, shipWidth, hasDimensions

class VesselModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Use as singleton.")
    QML_SINGLETON

    Q_PROPERTY(bool    loading READ loading NOTIFY loadingChanged FINAL)
    Q_PROPERTY(QString error   READ error   NOTIFY errorChanged   FINAL)

public:
    explicit VesselModel(QObject* parent = nullptr);

    void initialize(VesselApi* api);

    enum Roles {
        MmsiRole           = Qt::UserRole + 1,
        NameRole,
        LatRole,
        LonRole,
        DisplayHeadingRole,
        SpeedRole,
        ARole,
        BRole,
        CRole,
        DRole,
        ShipLengthRole,
        ShipWidthRole,
        HasDimensionsRole,
    };
    Q_ENUM(Roles)

    int     rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void fetch();

    bool    loading() const;
    QString error()   const;

signals:
    void loadingChanged();
    void errorChanged();
    void fetched();

private:
    void setLoading(bool value);
    void setError(const QString& message);

    VesselApi*      m_api     = nullptr;
    QVector<Vessel> m_vessels;
    bool            m_loading = false;
    QString         m_error;
};

#endif // VESSELMODEL_H
