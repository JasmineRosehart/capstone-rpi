#include "GPSThread.h"
#include <iostream>
#include <string>
#include <sstream>
#include <unistd.h>

// Uses ip-api.com free API — no key needed, works over WiFi/hotspot
// Returns approximate location based on your public IP address
// Accuracy: typically within a few km, good enough for tagging captures

GPSThread::GPSThread() : QThread(), running(false),
    lastLat("n/a"), lastLon("n/a") {}

GPSThread::~GPSThread() {}

void GPSThread::stop() {
    running = false;
}

QString GPSThread::getLastLat() {
    QMutexLocker locker(&gpsMutex);
    return lastLat;
}

QString GPSThread::getLastLon() {
    QMutexLocker locker(&gpsMutex);
    return lastLon;
}

bool GPSThread::fetchIPLocation(QString& lat, QString& lon) {
    // Use curl to hit ip-api.com — returns CSV: status,lat,lon
    // Example response: success,43.7001,-79.4163
    FILE* pipe = popen(
        "curl -s --max-time 5 'http://ip-api.com/csv/?fields=status,lat,lon'",
        "r"
    );

    if (!pipe) {
        std::cerr << "[GPSThread] Failed to run curl" << std::endl;
        return false;
    }

    char buffer[256];
    std::string result = "";
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    pclose(pipe);

    if (result.empty()) {
        std::cerr << "[GPSThread] Empty response from ip-api" << std::endl;
        return false;
    }

    // Parse CSV: status,lat,lon
    std::stringstream ss(result);
    std::string status, latStr, lonStr;
    std::getline(ss, status, ',');
    std::getline(ss, latStr, ',');
    std::getline(ss, lonStr, ',');

    // Remove any trailing whitespace/newlines
    while (!lonStr.empty() && (lonStr.back() == '\n' || lonStr.back() == '\r' || lonStr.back() == ' ')) {
        lonStr.pop_back();
    }

    if (status != "success") {
        std::cerr << "[GPSThread] ip-api returned: " << status << std::endl;
        return false;
    }

    lat = QString::fromStdString(latStr);
    lon = QString::fromStdString(lonStr);
    return true;
}

void GPSThread::run() {
    running = true;
    std::cerr << "[GPSThread] Started (IP geolocation mode)" << std::endl;

    while (running) {
        QString lat, lon;

        if (fetchIPLocation(lat, lon)) {
            gpsMutex.lock();
            lastLat = lat;
            lastLon = lon;
            gpsMutex.unlock();

            std::cout << "[GPSThread] Location: " << lat.toStdString()
                      << ", " << lon.toStdString() << std::endl;

            emit updateGPS(lat, lon, "IP");

            // Refresh every 30 seconds — IP location doesn't change often
            for (int i = 0; i < 30 && running; i++) {
                sleep(1);
            }
        } else {
            emit updateGPS("n/a", "n/a", "NO SIGNAL");

            // Wait 10 seconds before retrying — don't spam the API on failure
            for (int i = 0; i < 10 && running; i++) {
                sleep(1);
            }
        }
    }

    std::cerr << "[GPSThread] Stopped" << std::endl;
}