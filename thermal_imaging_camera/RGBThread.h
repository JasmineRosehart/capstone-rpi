#ifndef RGBTHREAD_H
#define RGBTHREAD_H

#include <QThread>
#include <QImage>
#include <QMutex>
#include <stdint.h>
#include <vector>

class RGBThread : public QThread
{
    Q_OBJECT

public:
    RGBThread();
    ~RGBThread();
    void stop();
    void run() override;

public slots:
    void saveCurrentFrame(QString timestamp);

signals:
    void updateRGBImage(QImage);

private:
    bool running;
    int width;
    int height;
    bool uploadToS3(const std::string& filename);

    QImage lastFrame;
    QMutex frameMutex;
};

#endif
