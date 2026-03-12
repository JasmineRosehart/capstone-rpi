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
| OS | Debian GNU/Linux 13 (Trixie) |

---

## GPIO Wiring

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

### 3. Verify camera is detected on I2C
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

## Troubleshooting

### Red box in top left corner
The app is running but getting no valid data from the camera. Check:
1. Wiring — especially that CS is on CE1 (Pin 26) not CE0 (Pin 24)
2. SPI is enabled: `ls /dev/spi*` should show `/dev/spidev0.1`
3. Camera detected on I2C: `sudo i2cdetect -y 1` should show `0x2A`
4. SPI buffer size is set in `/boot/firmware/cmdline.txt`

### All yellow image
Camera is connected but sending invalid/zero data. Usually means:
1. SPI port mismatch — verify code uses `spi_cs1_fd` not `spi_cs0_fd`
2. Wrong SPI mode — verify `SPI_MODE_3` is set in `SPI.cpp`

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
raspberrypi_video/
├── main.cpp              # Qt app entry point, argument parsing, UI setup
├── LeptonThread.cpp/h    # SPI read loop, frame processing, image output
├── Lepton_I2C.cpp/h      # I2C commands (FFC, reboot) via Lepton SDK
├── SPI.cpp/h             # Low-level SPI port open/close/configure
├── MyLabel.cpp/h         # Qt label widget with image update slot
├── Palettes.cpp/h        # Colormaps: rainbow, grayscale, ironblack
├── raspberrypi_video.pro # Qt project file
└── README.md             # This file
```

---