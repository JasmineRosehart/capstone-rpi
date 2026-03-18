# capstone-rpi — Thermal Imaging Module

Raspberry Pi 3B + FLIR Lepton 3.5 thermal camera system.  
Part of a larger capstone project integrating thermal imaging, RGB camera, GPS, and video streaming.

---

## Hardware

| Component | Details |
|---|---|
| Raspberry Pi | 3B |
| Thermal Camera | FLIR Lepton 3.5 |
| Breakout Board | FLIR Lepton Camera Breakout Board v2.0 (PN: 250-0577-00) |
| RGB Camera | Raspberry Pi Camera Module 2 (IMX219) |
| GPS Module | GY-NEO6MV2 (u-blox NEO-6M) |
| OS | Debian GNU/Linux 13 (Trixie) |

---

## GPIO Wiring

### Lepton 3.5 Thermal Camera

| Breakout Board Pin | Raspberry Pi Pin | Physical Pin |
|---|---|---|
| VIN (Power in) | 3.3V | Pin 1 |
| GND | Ground | Pin 6 |
| SDA | I2C1 SDA | Pin 3 |
| SCL | I2C1 SCL | Pin 5 |
| SPI_MISO | SPI0 MISO | Pin 21 |
| SPI_CLK | SPI0 SCLK | Pin 23 |
| SPI_CS | SPI0 **CE1** | Pin **26** |

> **Important:** Use CE1 (Pin 26), NOT CE0 (Pin 24). The code uses `/dev/spidev0.1`.

### Pi Camera Module 2

Connect the ribbon cable into the **CSI port** (the long thin connector between the HDMI and headphone jack on the Pi):
- Power off the Pi before connecting
- Lift the plastic latch on the CSI port
- Slide the ribbon cable in with the **blue side facing toward the HDMI port**
- Press the latch back down firmly
- Power the Pi back on

### GY-NEO6MV2 GPS Module (Hardware GPS)

The GPS module has 4 pins labeled on the board (left to right): `VCC  RX  TX  GND`

> **Note:** The pin headers must be soldered onto the board before connecting. Use a 2.54mm pitch single-row male header strip (break off 4 pins) and solder them into the 4 holes. Then connect with female-to-female jumper wires.

| GPS Module Pin | Raspberry Pi Pin | Physical Pin | Notes |
|---|---|---|---|
| VCC | **5V** | Pin 2 | Use 5V not 3.3V — the module needs 5V to power reliably |
| GND | Ground | Pin 6 | |
| TX | UART RX (GPIO15) | Pin 10 | GPS transmits → Pi receives |
| RX | UART TX (GPIO14) | Pin 8 | GPS receives → Pi transmits |

> **Important:** GPS TX connects to Pi RX and GPS RX connects to Pi TX — they always cross over. Using 3.3V for VCC may cause the power LED to flicker on/off and the module will not function reliably.

---

## Prerequisites

### 1. Enable SPI and I2C
```bash
sudo raspi-config
# Interface Options → SPI → Enable
# Interface Options → I2C → Enable
sudo reboot
```

### 2. Verify SPI and I2C are active
```bash
ls /dev/spi*
# Expected: /dev/spidev0.0  /dev/spidev0.1

ls /dev/i2c*
# Expected: /dev/i2c-1  /dev/i2c-2
```

### 3. Verify Lepton is detected on I2C
```bash
sudo apt-get install i2c-tools
sudo i2cdetect -y 1
# You should see a device at address 0x2A
```

### 4. Increase SPI buffer size (required on Debian Trixie)
```bash
sudo nano /boot/firmware/cmdline.txt
```
Add to the end of the existing line (do not add a new line):
```
spidev.bufsiz=65536
```
```bash
sudo reboot
```

### 5. Install Qt5 build tools (Qt4 is not available on Trixie)
```bash
sudo apt-get update
sudo apt-get install qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools
```

### 6. Enable the Pi Camera Module 2 (Debian Trixie)

> **Note:** On Debian Trixie, `raspi-config` does not show a "Legacy Camera" option. Enable the camera manually via config.txt instead.

```bash
sudo nano /boot/firmware/config.txt
```
Add this line at the bottom:
```
start_x=1
```
Save and reboot:
```bash
sudo reboot
```

### 7. Install rpicam-apps and verify camera detection

On Debian Trixie, the camera tools are named `rpicam-*` (not `libcamera-*`):
```bash
sudo apt install rpicam-apps
```

Verify the camera is detected:
```bash
rpicam-hello --list-cameras
```

You should see output like:
```
0 : imx219 [3280x2464 10-bit RGGB] (/base/soc/i2c0mux/i2c@1/imx219@10)
```

If `rpicam-hello` is not found after install, make sure you are **not inside a Python virtual environment**. Run `deactivate` first, then retry.

### 8. Install curl (required for IP geolocation GPS fallback)
```bash
sudo apt install curl
```

### 9. Install exiftool (required for writing GPS coordinates into image EXIF metadata)
```bash
sudo apt install libimage-exiftool-perl
```

Verify it installed:
```bash
exiftool --version
```

### 10. Hardware GPS setup — GY-NEO6MV2 (optional, replaces IP geolocation)

If using the physical GPS module instead of IP geolocation, follow these steps after wiring it up per the GPIO table above.

**Enable UART and disable the serial console:**
```bash
sudo raspi-config
# Interface Options → Serial Port
# "Would you like a login shell over serial?" → No
# "Would you like the serial port hardware to be enabled?" → Yes
sudo reboot
```

After reboot, confirm the settings show:
```
The serial login shell is disabled   ✅
The serial interface is enabled      ✅
```

**Disable the serial console service:**
```bash
sudo systemctl disable serial-getty@ttyAMA0.service
sudo systemctl stop serial-getty@ttyAMA0.service
```

**Check which serial device is active:**
```bash
ls -l /dev/serial*
# On Debian Trixie this typically shows:
# /dev/serial0 -> ttyS0
```

**Test raw GPS data:**
```bash
cat /dev/ttyS0
```

You should see NMEA sentences scrolling like:
```
$GNRMC,,V,,,,,,,,,,N*4D
$GNGGA,,,,,0,00,25.5,,,,,,*64
```

The `V` means no fix yet — this is normal indoors. Take the module near a window or outside and wait 1-3 minutes. The blue LED on the module will blink once per second when it has a satellite fix. Press `Ctrl+C` to stop.

**Install and configure gpsd:**
```bash
sudo apt install gpsd gpsd-clients
sudo nano /etc/default/gpsd
```

Set the contents to:
```
DEVICES="/dev/ttyS0"
GPSD_OPTIONS="-n"
START_DAEMON="true"
USBAUTO="false"
```

Start and enable gpsd:
```bash
sudo systemctl enable gpsd
sudo systemctl start gpsd
```

Verify with cgps:
```bash
cgps -s
```

Once you have a satellite fix outdoors you will see real latitude and longitude populate. Press `q` to quit.

**Switching the code from IP geolocation to hardware GPS:**

The current `GPSThread.cpp` uses IP geolocation via `ip-api.com`. To switch to the hardware GPS module, replace the `fetchIPLocation` function and `run()` loop in `GPSThread.cpp` with a version that reads directly from `/dev/ttyS0` and parses `$GNRMC` NMEA sentences. The `GPSThread.h` interface remains unchanged so no other files need to be modified.

---

## Build

```bash
cd thermal_imaging_camera
qmake && make
```

To clean and rebuild from scratch:
```bash
make sdkclean && make distclean
qmake && make
```

---

## Run

```bash
sudo nice -n -20 ./raspberrypi_video -tl 3
```

```bash
sudo ./raspberrypi_video -tl 3
```

> The `-tl 3` flag is required for Lepton 3.x cameras.  
> Running with `sudo nice -n -20` gives the process highest CPU priority for stable SPI communication.

### Optional Flags

| Flag | Description | Example |
|---|---|---|
| `-tl 3` | Select Lepton 3.x (required) | `-tl 3` |
| `-cm x` | Colormap: 1=rainbow, 2=grayscale, 3=ironblack | `-cm 1` |
| `-ss x` | SPI speed in MHz (10-30, default 20) | `-ss 18` |
| `-d x` | Log level 0-255 (255 = verbose) | `-d 255` |
| `-min x` | Override minimum scaling value | `-min 30000` |
| `-max x` | Override maximum scaling value | `-max 32000` |

---

## GPS Behaviour

The app uses `GPSThread` to obtain location coordinates. Two modes are supported:

**IP Geolocation (default, no hardware required):**
- Requires WiFi or hotspot connection
- Uses `ip-api.com` free API via `curl`
- Accuracy: typically within a few km
- Refreshes every 30 seconds automatically
- Coordinates displayed in the GPS status bar at the bottom of the window
- GPS coordinates are written into the EXIF metadata of every captured image using `exiftool`

**Hardware GPS (GY-NEO6MV2, higher accuracy):**
- Requires the GPS module to be wired and configured per the Hardware GPS Setup section above
- Accuracy: within a few metres once a satellite fix is acquired
- Must be outdoors or near a window to acquire a fix
- Blue LED on module blinks once per second when fix is active
- Coordinates are read from `/dev/ttyS0` as NMEA sentences

**Verifying GPS EXIF data in saved images:**
```bash
exiftool ir_images/ir_*.jpg | grep GPS
# Expected output:
# GPS Latitude  : 43 deg 41' 31.92" N
# GPS Longitude : 79 deg 25' 51.24" W
# GPS Position  : 43 deg 41' 31.92" N, 79 deg 25' 51.24" W
```

---

## Troubleshooting

### Red box in top left corner
The app is running but getting no valid data from the thermal camera. Check:
1. Wiring — especially that CS is on CE1 (Pin 26) not CE0 (Pin 24)
2. SPI is enabled: `ls /dev/spi*` should show `/dev/spidev0.1`
3. Lepton detected on I2C: `sudo i2cdetect -y 1` should show `0x2A`
4. SPI buffer size is set in `/boot/firmware/cmdline.txt`

### All yellow thermal image
Camera is connected but sending invalid/zero data. Usually means:
1. SPI port mismatch — verify code uses `spi_cs1_fd` not `spi_cs0_fd`
2. Wrong SPI mode — verify `SPI_MODE_3` is set in `SPI.cpp`

### RGB camera feed not showing
1. Verify camera is detected: `rpicam-hello --list-cameras` should show `imx219`
2. If not detected, check the ribbon cable is fully seated in the CSI port
3. Verify `start_x=1` is in `/boot/firmware/config.txt`
4. Check that `rpicam-vid` is available: `which rpicam-vid`

### `rpicam-hello: command not found` after installing rpicam-apps
You are likely inside a Python virtual environment. Run:
```bash
deactivate
sudo apt install rpicam-apps
rpicam-hello --list-cameras
```

### `libcamera0` package not found
On Debian Trixie, `libcamera0` has been replaced by versioned packages (`libcamera0.7`, etc.) and the app suite renamed to `rpicam-*`. Do not use `libcamera-apps` — use `rpicam-apps` instead.

### GPS shows `fetching...` and never updates
1. Check WiFi or hotspot is connected: `ping ip-api.com`
2. Verify curl is installed: `which curl`
3. Test manually: `curl -s 'http://ip-api.com/csv/?fields=status,lat,lon'`

### Hardware GPS shows no data in `cat /dev/ttyS0`
1. Check VCC is on Pin 2 (5V) not Pin 1 (3.3V)
2. Verify TX/RX are not swapped — GPS TX → Pi Pin 10, GPS RX → Pi Pin 8
3. Verify serial is enabled: `ls -l /dev/serial*` should show `/dev/serial0 -> ttyS0`
4. Make sure login shell over serial is disabled in raspi-config

### Hardware GPS shows data but `V` (no fix)
Normal behaviour indoors. Take the module outside or near a window and wait up to 3 minutes. The blue LED will blink once per second when a fix is acquired.

### GPS power LED flickers on/off
The module is not getting enough power from 3.3V. Move VCC wire from Pin 1 to Pin 2 (5V).

### Video drops out after ~1 minute
1. Check for loose jumper wires — this is the most common cause
2. Run with highest priority: `sudo nice -n -20 ./raspberrypi_video -tl 3`
3. Check Pi temperature: `watch -n 1 vcgencmd measure_temp` — should stay below 80°C
4. Monitor kernel SPI messages: `dmesg -w | grep -i spi`

### GLib-GObject CRITICAL warning in terminal
This is a harmless Qt display layer warning on Debian Trixie. It does not affect functionality and can be ignored.

### `[ERROR] Wrong segment number 0` in terminal
Normal behaviour for Lepton 3.5 — the camera occasionally sends discard packets. The code handles this automatically. As long as you see `[RECOVERED]` messages and the video looks correct, this is fine.

---

## Project Structure

```
thermal_imaging_camera/
├── main.cpp              # Qt app entry point, argument parsing, UI setup
├── LeptonThread.cpp/h    # SPI read loop, frame processing, image output
├── Lepton_I2C.cpp/h      # I2C commands (FFC, reboot) via Lepton SDK
├── SPI.cpp/h             # Low-level SPI port open/close/configure
├── MyLabel.cpp/h         # Qt label widget with image update slot
├── Palettes.cpp/h        # Colormaps: rainbow, grayscale, ironblack
├── RGBThread.cpp/h       # Pi Camera Module 2 capture via rpicam-vid pipe
├── GPSThread.cpp/h       # IP geolocation via ip-api.com (switchable to hardware GPS)
├── raspberrypi_video.pro # Qt project file
└── README.md             # This file
```

---