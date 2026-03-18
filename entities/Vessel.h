#ifndef VESSEL_H
#define VESSEL_H

#include <QString>
#include <QJsonObject>
#include "IPersistable.h"

class Vessel : public IPersistable
{
public:
    int     mmsi            = 0;
    QString name;
    double  lat             = 0.0;
    double  lon             = 0.0;
    int     heading         = 0;     // raw AIS heading
    double  cog             = 0.0;   // course over ground (degrees)
    double  displayHeading  = 0.0;   // resolved: cog if heading == 511
    double  speed           = 0.0;   // knots
    int     a               = 0;     // bow distance from antenna (m)
    int     b               = 0;     // stern distance from antenna (m)
    int     c               = 0;     // port distance from antenna (m)
    int     d               = 0;     // starboard distance from antenna (m)
    int     shipType        = 0;
    int     navstat         = 0;

    int     shipLength()  const { return a + b; }
    int     shipWidth()   const { return c + d; }
    bool    hasDimensions() const { return shipLength() > 0 && shipWidth() > 0; }

    QJsonObject toJson() const override
    {
        QJsonObject obj;
        obj["mmsi"]            = mmsi;
        obj["name"]            = name;
        obj["lat"]             = lat;
        obj["lon"]             = lon;
        obj["heading"]         = heading;
        obj["cog"]             = cog;
        obj["display_heading"] = displayHeading;
        obj["speed"]           = speed;
        obj["a"]               = a;
        obj["b"]               = b;
        obj["c"]               = c;
        obj["d"]               = d;
        obj["ship_type"]       = shipType;
        obj["navstat"]         = navstat;
        return obj;
    }

    void fromJson(const QJsonObject& obj) override
    {
        mmsi           = obj["mmsi"].toInt();
        name           = obj["name"].toString();
        lat            = obj["lat"].toDouble();
        lon            = obj["lon"].toDouble();
        heading        = obj["heading"].toInt();
        cog            = obj["cog"].toDouble();
        displayHeading = obj["display_heading"].toDouble();
        speed          = obj["speed"].toDouble();
        a              = obj["a"].toInt();
        b              = obj["b"].toInt();
        c              = obj["c"].toInt();
        d              = obj["d"].toInt();
        shipType       = obj["ship_type"].toInt();
        navstat        = obj["navstat"].toInt();
    }

    void fromAIS(const QJsonObject& ais)
    {
        mmsi    = ais["MMSI"].toInt();
        name    = ais["NAME"].toString();
        lat     = ais["LATITUDE"].toDouble();
        lon     = ais["LONGITUDE"].toDouble();
        heading = ais["HEADING"].toInt();
        cog     = ais["COURSE"].toDouble();
        displayHeading = (heading == 511) ? cog : static_cast<double>(heading);
        speed   = ais["SPEED"].toDouble();
        a       = ais["A"].toInt();
        b       = ais["B"].toInt();
        c       = ais["C"].toInt();
        d       = ais["D"].toInt();
        shipType = ais["TYPE"].toInt();
        navstat  = ais["NAVSTAT"].toInt();
    }
};

#endif // VESSEL_H
