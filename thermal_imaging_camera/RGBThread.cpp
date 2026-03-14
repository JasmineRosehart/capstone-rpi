#include "RGBThread.h"
#include <iostream>
#include <cstring>

RGBThread::RGBThread() : QThread(), running(false), width(640), height(480) {}
RGBThread::~RGBThread() {}

void RGBThread::stop() {
    running = false;
}

void RGBThread::run() {
    running = true;

    // Use rpicam-vid to pipe raw RGB to stdout
    FILE *pipe = popen(
        "rpicam-vid --width 640 --height 480 --codec yuv420 "
        "--framerate 10 --timeout 0 --nopreview -o - 2>/dev/null",
        "r"
    );

    if (!pipe) {
        std::cerr << "[RGBThread] Failed to open rpicam-vid pipe" << std::endl;
        return;
    }

    int frameSize = width * height * 3 / 2; // YUV420 size
    std::vector<uint8_t> yuvBuf(frameSize);

    while (running) {
        // Read one YUV420 frame
        size_t bytesRead = fread(yuvBuf.data(), 1, frameSize, pipe);
        if (bytesRead != (size_t)frameSize) {
            std::cerr << "[RGBThread] Incomplete frame read" << std::endl;
            break;
        }

        // Convert YUV420 to RGB888
        QImage frame(width, height, QImage::Format_RGB888);
        uint8_t *Y = yuvBuf.data();
        uint8_t *U = Y + width * height;
        uint8_t *V = U + (width * height) / 4;

        auto clamp = [](int v) -> uint8_t {
            return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
        };

        for (int y = 0; y < height; y++) {
            uint8_t *row = frame.scanLine(y);
            for (int x = 0; x < width; x++) {
                int Yval = Y[y * width + x];
                int Uval = U[(y/2) * (width/2) + (x/2)] - 128;
                int Vval = V[(y/2) * (width/2) + (x/2)] - 128;

                row[x*3+0] = clamp(Yval + 1.402  * Vval);
                row[x*3+1] = clamp(Yval - 0.344  * Uval - 0.714 * Vval);
                row[x*3+2] = clamp(Yval + 1.772  * Uval);
            }
        }
        
        frameMutex.lock();
        lastFrame = frame.copy();
        frameMutex.unlock();

        emit updateRGBImage(frame);
    }

    pclose(pipe);
}

void RGBThread::saveCurrentFrame(QString timestamp) {
    frameMutex.lock();
    if (!lastFrame.isNull()) {
        QDir().mkdir("rgb_images");

        // Use the 'timestamp' passed from the lambda instead of calling QDateTime again
        QString qPath = QString("rgb_images/rgb_%1.jpg").arg(timestamp);
        
        std::string localFile = qPath.toStdString();

        if (lastFrame.save(qPath, "JPG")) {
            std::cout << "[RGB] Saved locally: " << localFile << std::endl;
            uploadToS3(localFile);
        }
    }
    frameMutex.unlock();
}

bool RGBThread::uploadToS3(const std::string& filename) {
    // Construct the command
    // We point to the 'rgb-images' folder in your bucket
    std::string command = "aws s3 cp " + filename + 
                          " s3://fire-ml-bucket/inputs/rgb-images/" + 
                          " --region us-east-2";

    // Run the command
    int result = system(command.c_str());
    
    if (result == 0) {
        std::cout << "[RGB] Successfully uploaded to S3." << std::endl;
        return true;
    } else {
        std::cerr << "[RGB] AWS CLI Error: " << result << std::endl;
        return false;
    }
}
