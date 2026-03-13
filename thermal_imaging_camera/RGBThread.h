#ifndef RGBTHREAD_H
#define RGBTHREAD_H

#include <QThread>
#include <QImage>
#include <stdint.h>

class RGBThread : public QThread
{
    Q_OBJECT

public:
    RGBThread();
    ~RGBThread();
    void stop();
    void run() override;

signals:
    void updateRGBImage(QImage);

private:
    bool running;
    int width;
    int height;
};

#endif