#include "GPSThread.h"
#include <iostream>
#include <string>
#include <sstream>
#include <vector>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <ctime>

// Hardware GPS: GY-NEO6MV2 (u-blox NEO-6M) via UART on /dev/ttyS0
// Parses $GPRMC / $GNRMC NMEA sentences for a real GPS fix (~2-5m accuracy)
// Falls back to ip-api.com (city-level, ~1-5km) if no hardware fix is available

static const char* SERIAL_PORT  = "/dev/ttyS0";
static const int   HW_TIMEOUT_S = 60; // seconds to wait for hardware fix before falling back

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

// Convert NMEA coordinate format (DDMM.MMMM or DDDMM.MMMM) to decimal degrees
static double nmeaToDecimal(const std::string& raw, const std::string& dir) {
    if (raw.empty()) return 0.0;
    size_t dotPos = raw.find('.');
    if (dotPos == std::string::npos || dotPos < 2) return 0.0;

    // Degrees = digits before the last two pre-decimal digits (which are minutes)
    int degDigits = (int)dotPos - 2;
    double degrees = std::stod(raw.substr(0, degDigits));
    double minutes = std::stod(raw.substr(degDigits));
    double decimal = degrees + minutes / 60.0;

    if (dir == "S" || dir == "W") decimal = -decimal;
    return decimal;
}

// Parse one NMEA sentence — returns true if it's a valid $GPRMC/$GNRMC with an active fix
static bool parseNMEA(const std::string& sentence, QString& lat, QString& lon) {
    if (sentence.size() < 6 || sentence[0] != '$') return false;

    std::string type = sentence.substr(1, 5);
    if (type != "GPRMC" && type != "GNRMC") return false;

    std::vector<std::string> fields;
    std::stringstream ss(sentence);
    std::string field;
    while (std::getline(ss, field, ',')) {
        fields.push_back(field);
    }

    // $GNRMC: index 2 = status (A=fix, V=void), 3=lat, 4=N/S, 5=lon, 6=E/W
    if (fields.size() < 7) return false;
    if (fields[2] != "A") return false;

    const std::string& latRaw = fields[3];
    const std::string& latDir = fields[4];
    const std::string& lonRaw = fields[5];
    const std::string& lonDir = fields[6];

    if (latRaw.empty() || lonRaw.empty()) return false;

    try {
        double latDec = nmeaToDecimal(latRaw, latDir);
        double lonDec = nmeaToDecimal(lonRaw, lonDir);
        lat = QString::number(latDec, 'f', 6);
        lon = QString::number(lonDec, 'f', 6);
        return true;
    } catch (...) {
        return false;
    }
}

bool GPSThread::fetchHardwareGPS(QString& lat, QString& lon) {
    int fd = open(SERIAL_PORT, O_RDONLY | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        std::cerr << "[GPSThread] Cannot open " << SERIAL_PORT
                  << " — no hardware GPS, falling back to IP" << std::endl;
        return false;
    }

    // Configure serial port: 9600 baud, 8N1, no flow control
    struct termios tty;
    if (tcgetattr(fd, &tty) != 0) {
        std::cerr << "[GPSThread] tcgetattr failed" << std::endl;
        close(fd);
        return false;
    }
    cfsetispeed(&tty, B9600);
    cfsetospeed(&tty, B9600);
    tty.c_cflag  = (tty.c_cflag & ~CSIZE) | CS8;
    tty.c_cflag |= CLOCAL | CREAD;
    tty.c_cflag &= ~(PARENB | PARODD | CSTOPB | CRTSCTS);
    tty.c_iflag &= ~(IXON | IXOFF | IXANY | IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL);
    tty.c_lflag  = 0;
    tty.c_oflag  = 0;
    tcsetattr(fd, TCSANOW, &tty);

    std::cerr << "[GPSThread] Waiting for hardware GPS fix (up to "
              << HW_TIMEOUT_S << "s)..." << std::endl;

    std::string lineBuf;
    time_t start = time(nullptr);
    char ch;

    while (running && (time(nullptr) - start) < HW_TIMEOUT_S) {
        ssize_t n = read(fd, &ch, 1);
        if (n <= 0) {
            usleep(10000); // 10ms
            continue;
        }
        if (ch == '\n') {
            if (!lineBuf.empty() && lineBuf.back() == '\r') lineBuf.pop_back();
            if (parseNMEA(lineBuf, lat, lon)) {
                close(fd);
                return true;
            }
            lineBuf.clear();
        } else {
            lineBuf += ch;
        }
    }

    close(fd);
    std::cerr << "[GPSThread] No hardware GPS fix within timeout, falling back to IP" << std::endl;
    return false;
}

bool GPSThread::fetchIPLocation(QString& lat, QString& lon) {
    FILE* pipe = popen(
        "curl -s --max-time 5 'http://ip-api.com/csv/?fields=status,lat,lon'",
        "r"
    );

    if (!pipe) {
        std::cerr << "[GPSThread] Failed to run curl" << std::endl;
        return false;
    }

    char buffer[256];
    std::string result;
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

    auto trimTrailing = [](std::string& s) {
        while (!s.empty() && (s.back() == '\n' || s.back() == '\r' || s.back() == ' '))
            s.pop_back();
    };
    trimTrailing(latStr);
    trimTrailing(lonStr);

    if (status != "success") {
        std::cerr << "[GPSThread] ip-api returned: " << status << std::endl;
        return false;
    }

    try {
        lat = QString::number(std::stod(latStr), 'f', 6);
        lon = QString::number(std::stod(lonStr), 'f', 6);
    } catch (const std::exception& e) {
        std::cerr << "[GPSThread] Failed to parse ip-api lat/lon: " << e.what() << std::endl;
        return false;
    }
    return true;
}

void GPSThread::run() {
    running = true;
    std::cerr << "[GPSThread] Started" << std::endl;

    while (running) {
        QString lat, lon;
        QString source;

        if (fetchHardwareGPS(lat, lon)) {
            source = "GPS";
        } else if (fetchIPLocation(lat, lon)) {
            source = "IP";
        } else {
            emit updateGPS("n/a", "n/a", "NO SIGNAL");
            for (int i = 0; i < 10 && running; i++) sleep(1);
            continue;
        }

        {
            QMutexLocker locker(&gpsMutex);
            lastLat = lat;
            lastLon = lon;
        }

        std::cout << "[GPSThread] Location (" << source.toStdString() << "): "
                  << lat.toStdString() << ", " << lon.toStdString() << std::endl;

        emit updateGPS(lat, lon, source);

        // Hardware GPS updates every 5s, IP fallback every 30s
        int interval = (source == "GPS") ? 5 : 30;
        for (int i = 0; i < interval && running; i++) sleep(1);
    }

    std::cerr << "[GPSThread] Stopped" << std::endl;
}
