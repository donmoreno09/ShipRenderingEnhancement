#include "VesselModel.h"
#include "networking/VesselApi.h"
#include <QDebug>

VesselModel::VesselModel(QObject* parent)
    : QAbstractListModel(parent) {}

void VesselModel::initialize(VesselApi* api)
{
    m_api = api;
}

int VesselModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid()) return 0;
    return m_vessels.size();
}

QVariant VesselModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid()) return {};
    if (index.row() < 0 || index.row() >= m_vessels.size()) return {};

    const Vessel& v = m_vessels[index.row()];

    switch (role) {
    case MmsiRole:           return v.mmsi;
    case NameRole:           return v.name;
    case LatRole:            return v.lat;
    case LonRole:            return v.lon;
    case DisplayHeadingRole: return v.displayHeading;
    case SpeedRole:          return v.speed;
    case ARole:              return v.a;
    case BRole:              return v.b;
    case CRole:              return v.c;
    case DRole:              return v.d;
    case ShipLengthRole:     return v.shipLength();
    case ShipWidthRole:      return v.shipWidth();
    case HasDimensionsRole:  return v.hasDimensions();
    }
    return {};
}

QHash<int, QByteArray> VesselModel::roleNames() const
{
    return {
        { MmsiRole,           "mmsi"           },
        { NameRole,           "name"           },
        { LatRole,            "lat"            },
        { LonRole,            "lon"            },
        { DisplayHeadingRole, "displayHeading" },
        { SpeedRole,          "speed"          },
        { ARole,              "a"              },
        { BRole,              "b"              },
        { CRole,              "c"              },
        { DRole,              "d"              },
        { ShipLengthRole,     "shipLength"     },
        { ShipWidthRole,      "shipWidth"      },
        { HasDimensionsRole,  "hasDimensions"  },
    };
}

void VesselModel::fetch()
{
    if (!m_api) return;
    qDebug().noquote() << "[VesselModel] fetch()";
    setLoading(true);
    setError({});

    m_api->fetchAll([this](const QList<Vessel>& vessels) {
        beginResetModel();
        m_vessels = QVector<Vessel>(vessels.begin(), vessels.end());
        endResetModel();
        setLoading(false);
        qDebug().noquote() << "[VesselModel] fetch → loaded" << m_vessels.size() << "vessels";
        emit fetched();
    }, [this](const ErrorResult& err) {
        qWarning().noquote() << "[VesselModel] fetch → error:" << err.message;
        setLoading(false);
        setError(err.message);
    });
}

bool    VesselModel::loading() const { return m_loading; }
QString VesselModel::error()   const { return m_error; }

void VesselModel::setLoading(bool value)
{
    if (m_loading == value) return;
    m_loading = value;
    emit loadingChanged();
}

void VesselModel::setError(const QString& message)
{
    if (m_error == message) return;
    m_error = message;
    emit errorChanged();
}
