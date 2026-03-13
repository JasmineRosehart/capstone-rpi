#include "RGBThread.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>
#include <cstring>
#include <iostream>
#include <QImage>

#define RGB_DEVICE "/dev/video0"
#define NUM_BUFFERS 4

struct Buffer {
    void   *start;
    size_t  length;
};

RGBThread::RGBThread() : QThread(), running(false), width(640), height(480) {}
RGBThread::~RGBThread() {}

void RGBThread::stop() {
    running = false;
}

void RGBThread::run() {
    running = true;

    int fd = open(RGB_DEVICE, O_RDWR);
    if (fd < 0) {
        std::cerr << "[RGBThread] Failed to open " << RGB_DEVICE << std::endl;
        return;
    }

    // Set format to YUYV (universally supported by Pi cam via V4L2)
    struct v4l2_format fmt = {};
    fmt.type                = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width       = width;
    fmt.fmt.pix.height      = height;
    fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
    fmt.fmt.pix.field       = V4L2_FIELD_INTERLACED;
    if (ioctl(fd, VIDIOC_S_FMT, &fmt) < 0) {
        std::cerr << "[RGBThread] VIDIOC_S_FMT failed" << std::endl;
        close(fd); return;
    }

    // Request mmap buffers
    struct v4l2_requestbuffers req = {};
    req.count  = NUM_BUFFERS;
    req.type   = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (ioctl(fd, VIDIOC_REQBUFS, &req) < 0) {
        std::cerr << "[RGBThread] VIDIOC_REQBUFS failed" << std::endl;
        close(fd); return;
    }

    // Map buffers
    Buffer buffers[NUM_BUFFERS];
    for (int i = 0; i < NUM_BUFFERS; i++) {
        struct v4l2_buffer buf = {};
        buf.type   = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index  = i;
        ioctl(fd, VIDIOC_QUERYBUF, &buf);
        buffers[i].length = buf.length;
        buffers[i].start  = mmap(nullptr, buf.length,
                                  PROT_READ | PROT_WRITE, MAP_SHARED,
                                  fd, buf.m.offset);
        ioctl(fd, VIDIOC_QBUF, &buf);
    }

    // Start streaming
    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    ioctl(fd, VIDIOC_STREAMON, &type);

    while (running) {
        struct v4l2_buffer buf = {};
        buf.type   = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;

        if (ioctl(fd, VIDIOC_DQBUF, &buf) < 0) {
            std::cerr << "[RGBThread] VIDIOC_DQBUF failed" << std::endl;
            break;
        }

        // Convert YUYV -> RGB888
        uint8_t *src = (uint8_t *)buffers[buf.index].start;
        QImage frame(width, height, QImage::Format_RGB888);
        for (int y = 0; y < height; y++) {
            uint8_t *row = frame.scanLine(y);
            for (int x = 0; x < width; x += 2) {
                int idx = (y * width + x) * 2;
                int Y0 = src[idx + 0];
                int U  = src[idx + 1] - 128;
                int Y1 = src[idx + 2];
                int V  = src[idx + 3] - 128;

                auto clamp = [](int v) -> uint8_t {
                    return (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
                };

                row[x*3+0] = clamp(Y0 + 1.402*V);
                row[x*3+1] = clamp(Y0 - 0.344*U - 0.714*V);
                row[x*3+2] = clamp(Y0 + 1.772*U);

                row[(x+1)*3+0] = clamp(Y1 + 1.402*V);
                row[(x+1)*3+1] = clamp(Y1 - 0.344*U - 0.714*V);
                row[(x+1)*3+2] = clamp(Y1 + 1.772*U);
            }
        }

        emit updateRGBImage(frame);

        ioctl(fd, VIDIOC_QBUF, &buf);
    }

    // Cleanup
    ioctl(fd, VIDIOC_STREAMOFF, &type);
    for (int i = 0; i < NUM_BUFFERS; i++)
        munmap(buffers[i].start, buffers[i].length);
    close(fd);
}