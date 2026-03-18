#include <QApplication>
#include <QThread>
#include <QMutex>
#include <QMessageBox>
#include <QColor>
#include <QLabel>
#include <QtDebug>
#include <QString>
#include <QPushButton>
#include <QDateTime>
#include <signal.h>
#include <iostream>

#include "LeptonThread.h"
#include "MyLabel.h"
#include "RGBThread.h"
#include "GPSThread.h"


void printUsage(char *cmd) {
    char *cmdname = basename(cmd);
    printf("Usage: %s [OPTION]...\n"
           " -h      display this help and exit\n"
           " -cm x   select colormap\n"
           "           1 : rainbow\n"
           "           2 : grayscale\n"
           "           3 : ironblack [default]\n"
           " -tl x   select type of Lepton\n"
           "           2 : Lepton 2.x [default]\n"
           "           3 : Lepton 3.x\n"
           "               [for your reference] Please use nice command\n"
           "                 e.g. sudo nice -n 0 ./%s -tl 3\n"
           " -ss x   SPI bus speed [MHz] (10 - 30)\n"
           "           20 : 20MHz [default]\n"
           " -min x  override minimum value for scaling (0 - 65535)\n"
           "           [default] automatic scaling range adjustment\n"
           "           e.g. -min 30000\n"
           " -max x  override maximum value for scaling (0 - 65535)\n"
           "           [default] automatic scaling range adjustment\n"
           "           e.g. -max 32000\n"
           " -d x    log level (0-255)\n"
           "", cmdname, cmdname);
    return;
}

int main( int argc, char **argv )
{
    signal(SIGPIPE, SIG_IGN); // prevent rpicam-vid pipe crash

    int typeColormap = 3; // colormap_ironblack
    int typeLepton = 2;   // Lepton 2.x
    int spiSpeed = 20;    // SPI bus speed 20MHz
    int rangeMin = -1;
    int rangeMax = -1;
    int loglevel = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0) {
            printUsage(argv[0]);
            exit(0);
        }
        else if (strcmp(argv[i], "-d") == 0) {
            int val = 3;
            if ((i + 1 != argc) && (strncmp(argv[i + 1], "-", 1) != 0)) {
                val = std::atoi(argv[i + 1]);
                i++;
            }
            if (0 <= val) loglevel = val & 0xFF;
        }
        else if ((strcmp(argv[i], "-cm") == 0) && (i + 1 != argc)) {
            int val = std::atoi(argv[i + 1]);
            if ((val == 1) || (val == 2)) { typeColormap = val; i++; }
        }
        else if ((strcmp(argv[i], "-tl") == 0) && (i + 1 != argc)) {
            int val = std::atoi(argv[i + 1]);
            if (val == 3) { typeLepton = val; i++; }
        }
        else if ((strcmp(argv[i], "-ss") == 0) && (i + 1 != argc)) {
            int val = std::atoi(argv[i + 1]);
            if ((10 <= val) && (val <= 30)) { spiSpeed = val; i++; }
        }
        else if ((strcmp(argv[i], "-min") == 0) && (i + 1 != argc)) {
            int val = std::atoi(argv[i + 1]);
            if ((0 <= val) && (val <= 65535)) { rangeMin = val; i++; }
        }
        else if ((strcmp(argv[i], "-max") == 0) && (i + 1 != argc)) {
            int val = std::atoi(argv[i + 1]);
            if ((0 <= val) && (val <= 65535)) { rangeMax = val; i++; }
        }
    }

    // Create the app
    QApplication a(argc, argv);

    QWidget *myWidget = new QWidget;

    // Create placeholder image for thermal label
    QImage myImage(320, 240, QImage::Format_RGB888);
    QRgb red = qRgb(255, 0, 0);
    for (int i = 0; i < 80; i++)
        for (int j = 0; j < 60; j++)
            myImage.setPixel(i, j, red);

    // Thermal camera label (left)
    MyLabel myLabel(myWidget);
    myLabel.setGeometry(10, 10, 640, 480);
    myLabel.setPixmap(QPixmap::fromImage(myImage));

    // RGB camera label (right)
    MyLabel rgbLabel(myWidget);
    rgbLabel.setGeometry(660, 10, 640, 480);

    // GPS status label (bottom, full width)
    QLabel *gpsLabel = new QLabel("GPS: fetching...", myWidget);
    gpsLabel->setGeometry(10, 500, 1290, 25);
    gpsLabel->setStyleSheet("color: black; padding: 2px;");

    // Capture button (below thermal, left side)
    QPushButton *saveButton = new QPushButton("Capture Image", myWidget);
    saveButton->setGeometry(595, 488, 120, 28);

    // Set window size to fit everything
    myWidget->setGeometry(400, 300, 1310, 535);

    // RGB Thread 
    RGBThread *rgbThread = new RGBThread();
    QObject::connect(rgbThread, SIGNAL(updateRGBImage(QImage)),
                     &rgbLabel, SLOT(setImage(QImage)));
    rgbThread->start();

    // GPS Thread 
    GPSThread *gpsThread = new GPSThread();
    QObject::connect(gpsThread, &GPSThread::updateGPS,
        [gpsLabel](QString lat, QString lon, QString source) {
            gpsLabel->setText("GPS [" + source + "]  Lat: " + lat + "  Lon: " + lon);
        });
    gpsThread->start();

    // Lepton Thermal Thread
    LeptonThread *thread = new LeptonThread();
    thread->setLogLevel(loglevel);
    thread->useColormap(typeColormap);
    thread->useLepton(typeLepton);
    thread->useSpiSpeedMhz(spiSpeed);
    thread->setAutomaticScalingRange();
    if (0 <= rangeMin) thread->useRangeMinValue(rangeMin);
    if (0 <= rangeMax) thread->useRangeMaxValue(rangeMax);
    QObject::connect(thread, SIGNAL(updateImage(QImage)),
                     &myLabel, SLOT(setImage(QImage)));
    thread->start();

    // Capture button: save both frames with shared timestamp and log GPS at capture time
	QObject::connect(saveButton, &QPushButton::clicked,
		[thread, rgbThread, gpsThread]() {
			QString timestamp = QDateTime::currentDateTime()
									.toString("yyyyMMdd_hhmmss");
			QString lat = gpsThread->getLastLat();
			QString lon = gpsThread->getLastLon();

			std::cout << "[GPS at capture] Lat: " << lat.toStdString()
					<< "  Lon: " << lon.toStdString() << std::endl;

			thread->saveCurrentFrame(timestamp, lat, lon);
			rgbThread->saveCurrentFrame(timestamp, lat, lon);
		});

    myWidget->show();
    return a.exec();
}