# CircuitValley sensor drivers for Raspberry Pi

V4L2 kernel drivers for the CircuitValley camera modules, packaged as DKMS
modules with device-tree overlays for the Raspberry Pi CSI connector.

Eight sensors are supported. Each has its own directory holding the driver, the
overlay, a DKMS package and a per-sensor README with the detail for that part.

## Sensors

| Sensor | Resolution | Link frequency | Lanes | Boards |
| ------ | ---------- | -------------- | ----- | ------ |
| [imx283](imx283/README.md)   | 5472 x 3648 | 360 - 720 MHz (720 - 1440 Mbps/lane) | 4 | Pi 5, CM4, CM5 |
| [imx294](imx294/README.md)   | 4176 x 2824 | 480 - 600 MHz (960 - 1728 Mbps/lane) | 4 | Pi 5, CM4, CM5 |
| [imx477](imx477/README.md)   | 4056 x 3040 | 450 - 624 MHz (900 - 1248 Mbps/lane) | 2 or 4 | all |
| [imx565](imx565/README.md)   | 4128 x 3008 | 297 - 594 MHz (594 - 1188 Mbps/lane) | 2 or 4 | all |
| [imx568](imx568/README.md)   | 2472 x 2064 | 297 - 594 MHz (594 - 1188 Mbps/lane) | 2 or 4 | all |
| [imx585](imx585/README.md)   | 3840 x 2160 | 297 - 891 MHz (594 - 1782 Mbps/lane) | 2 or 4 | all |
| [imx678](imx678/README.md)   | 3840 x 2160 | 297 - 891 MHz (594 - 1782 Mbps/lane) | 2 or 4 | all |
| [ox08b40](ox08b40/README.md) | 3840 x 2160 | 480 MHz (960 Mbps/lane), fixed | 4 | Pi 5, CM4, CM5 |

Link frequency is the range the driver accepts, not a continuous sweep: each
driver takes a fixed set of values, listed in its own README. The default is the
rate the CircuitValley board is qualified at. Raising it does not automatically
raise the frame rate, because the receiver is usually the limit before the
sensor is.

## Which board, and why

| Board | CSI receiver | Data lanes on the camera connector |
| ----- | ------------ | ---------------------------------- |
| Raspberry Pi 5 | rp1-cfe | 4, on both CAM/DISP connectors |
| CM5 carrier | rp1-cfe | 4 on CAM1 |
| CM4 carrier | bcm2835-unicam | 4 on CAM1 |
| Raspberry Pi 4 | bcm2835-unicam | 2 |

Lane count is what decides board support. The imx283, imx294 and ox08b40 drivers
have no 2-lane mode, so they need a connector that wires all four lanes: a
Raspberry Pi 5, a CM4 or a CM5 carrier. A Raspberry Pi 4's camera connector wires
only two lanes, so it can run the other five sensors and not those three.

The receiver also caps throughput. RP1 on the Pi 5 and CM5 handles roughly
400 Mpix/s without overclocking, which is what limits the frame rate at full
resolution rather than any sensor register. The Pi 4's unicam has no RAW16 path
at all.

Kernel 6.12 or newer is required. One source tree covers 6.12 through 6.18 and
later, so there are no per-kernel branches.

## Installing the driver

One command installs the build dependencies, the DKMS module, the overlay and
the config.txt entry:

```bash
git clone https://github.com/circuitvalley/chc5_sensor_v4l2_drivers
cd chc5_sensor_v4l2_drivers
sudo ./setup.sh imx585           # Pi 5: connector cam0; add --cam1 for the other one
sudo reboot
sudo ./setup.sh --check imx585   # after the reboot
```

Options: `--cam0` / `--cam1` pick the connector, `--mono` selects the
monochrome imx585 or imx678, `--2lane` is added automatically on a Pi 4,
`--link-frequency HZ` picks another rate from the sensor's table, and
`--option NAME[=VALUE]` passes any other overlay parameter, for example
`--option rotation=180`. `sudo ./setup.sh --help` lists them all.

The script runs `apt-get` for `dkms`, `device-tree-compiler`,
`build-essential` and the kernel headers package that tracks kernel upgrades,
so DKMS can rebuild the module after the next `apt full-upgrade`. On a machine
without internet access install those yourself and pass `--no-deps`.

What it writes to `/boot/firmware/config.txt` is one managed block:

```
# >>> circuitvalley sensor >>>
[all]
camera_auto_detect=0
dtoverlay=imx585,cam0,always-on
# <<< circuitvalley sensor <<<
```

Re-running replaces that block and touches nothing else. The stock
`camera_auto_detect=1` line is commented out, since autodetection fights the
overlay, and `--uninstall` puts it back. `always-on` is currently needed on
every module: without it the camera regulator stays off and the I2C bus reads
back empty. For imx294 the script also sets `link-frequency=600000000`,
because the RP1 receiver on a Pi 5 receives nothing at the sensor's 480 MHz
default.

`sudo ./setup.sh --all` installs every module without a config.txt entry,
useful if you swap sensors; then pick one with
`sudo ./setup.sh <sensor> --config-only`. `<sensor>/setup.sh` on its own
installs just the module, for people who manage config.txt themselves; the
per-sensor READMEs describe that path and the overlay parameters.

For imx477 and imx283 the kernel already ships a driver of the same name.
`setup.sh` forces the DKMS install over it and checks that the right module
won; you can confirm it yourself:

```bash
modinfo imx477 | grep filename        # must resolve under updates/dkms/
```

After changing a module, reboot rather than unloading and reloading it. Hot
swapping corrupts the media graph on rp1-cfe.

## Checking the driver loaded

```bash
dmesg | grep -i imx585
media-ctl -p | grep -i imx585         # the sensor should appear as an entity
v4l2-ctl --list-devices
```

## libcamera and rpicam-apps

The drivers alone give you raw V4L2 capture. Everything that goes through
libcamera needs the CircuitValley libcamera fork, because Raspberry Pi's
libcamera refuses any sensor it has no CamHelper for, and even for the two it
knows it applies the wrong gain law to these drivers.

    https://github.com/circuitvalley/libcamera-circuitvalley

### What works with and without it

| | Stock Raspberry Pi OS | With the fork |
| --- | --- | --- |
| Raw capture over V4L2: `v4l2-ctl`, `media-ctl`, GStreamer `v4l2src`, `tools/pi_capture` | works, all eight sensors | works |
| Sensor controls over V4L2: exposure, gain, blanking, link frequency | works | works |
| `rpicam-hello`, `rpicam-vid`, `rpicam-still` | imx294, imx565, imx568, imx585, imx678, ox08b40: `No cameras available!` imx477: runs, but the gain is wrong, AGC pinned at maximum or about three times off | all eight, with auto exposure, auto white balance and the measured colour matrices |
| Picamera2 | same as rpicam-apps | all eight through the fork's Python bindings, not yet verified on the bench |
| GStreamer `libcamerasrc` | same as rpicam-apps | works, built with `-Dgstreamer=enabled` |
| Mode list in libcamera | | one size per sensor for imx565, imx568, imx585 and imx678, since the drivers advertise a continuous range; V4L2 is not limited |

On a fresh Raspberry Pi OS Trixie image with the imx568 installed, `rpicam-hello
--list-cameras` prints `No cameras available!` while `v4l2-ctl` streams full
frames. That is the expected stock behaviour, not a driver fault.

### What the fork contains

Raspberry Pi's own libcamera (v0.7.2+rpt20260817) plus two commits: eight
CamHelpers that speak the drivers' gain unit, tenths of a dB, and tuning files
for imx294, imx565, imx568, imx585, imx678 and ox08b40 with colour measured
against a ColorChecker under three lamps. imx477 and imx283 keep Raspberry Pi's
tuning files; only the gain functions of their helpers are patched. The tuning
files carry placeholder noise, lens-shading and lux models.

### Installing the fork

Build both libcamera and rpicam-apps from source, following Raspberry Pi's
documentation with this repository in place of theirs. Both are needed: the
fork is libcamera 0.7.2, and the rpicam-apps package in the distribution is
built against the distribution's 0.7.1. On a Raspberry Pi 5 the two builds take
about 12 and 6 minutes; the Pi needs internet access for the build dependencies.

```bash
sudo apt install -y git python3-pip python3-jinja2 python3-yaml python3-ply \
    libboost-dev libgnutls28-dev openssl libtiff-dev pybind11-dev \
    qtbase5-dev libqt5core5a libqt5widgets5 meson cmake ninja-build \
    libglib2.0-dev libgstreamer-plugins-base1.0-dev
git clone https://github.com/circuitvalley/libcamera-circuitvalley.git
cd libcamera-circuitvalley
meson setup build --buildtype=release -Dgstreamer=enabled -Dpycamera=enabled
sudo ninja -C build install
sudo ldconfig
```

Then rpicam-apps, at the version the bench validated against the fork:

```bash
git clone --branch v1.12.0 https://github.com/raspberrypi/rpicam-apps.git
cd rpicam-apps
meson setup build
meson compile -C build
sudo meson install -C build
sudo ldconfig
rpicam-hello --list-cameras
```

Raspberry Pi's page lists the rpicam-apps build dependencies and the meson
options for the preview and encoder back ends:
https://www.raspberrypi.com/documentation/computers/camera_software.html

Both install under `/usr/local`, so the distribution packages stay on disk and
`apt` keeps working, but at runtime the fork takes precedence. To go back to
the stock stack, run `sudo ninja -C build uninstall` in both build directories
and `sudo ldconfig`.

### What the fork changes for other cameras

- The imx477 CamHelper is patched, so **a genuine Raspberry Pi HQ Camera on the
  same system is also driven by the patched gain law.** The existing imx477
  tuning files are untouched, only the helper.
- Installing our imx477 driver replaces the in-kernel one system wide, so an HQ
  Camera runs on our driver too.

If you need a stock HQ Camera to behave exactly as Raspberry Pi ships it, do not
install the imx477 driver or the fork on that system.

### Pi 4 and CM4

The tuning files are complete for RP1, which covers the Pi 5 and CM5. For the Pi
4 and CM4 the fork carries tuning only for imx283 and imx477, so on those boards
the other six sensors are raw V4L2 only for now.

