#ifndef GPSTHREAD_H
#define GPSTHREAD_H

#include <QThread>
#include <QString>
#include <QMutex>

class GPSThread : public QThread
{
    Q_OBJECT

public:
    GPSThread();
    ~GPSThread();
    void stop();
    void run() override;

    QString getLastLat();
    QString getLastLon();

signals:
    void updateGPS(QString lat, QString lon, QString source);

private:
    bool running;
    QString lastLat;
    QString lastLon;
    QMutex gpsMutex;

    bool fetchIPLocation(QString& lat, QString& lon);
};

#endif
