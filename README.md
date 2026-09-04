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

Install the build dependencies, then run the setup script for the sensor you
have. `--all` installs every driver, which is useful if you swap modules.

```bash
sudo apt install linux-headers-$(uname -r) dkms device-tree-compiler git
git clone https://github.com/circuitvalley/chc5_sensor_v4l2_drivers
cd chc5_sensor_v4l2_drivers
./setup.sh imx585          # or ./setup.sh --all
```

Add the overlay to `/boot/firmware/config.txt`, turning off camera
autodetection so it does not fight the overlay:

```
camera_auto_detect=0
dtoverlay=imx585,cam0,always-on
```

Reboot. Each sensor's README lists the overlay options for that part, including
its link frequencies and any options only it has.

Two notes that apply to every module:

- `always-on` is currently needed on all of them. Without it the camera
  regulator stays off and the I2C bus reads back empty.
- Use `cam0` or `cam1` explicitly to match the connector you plugged into.

For imx477 and imx283 the kernel already ships a driver of the same name.
`setup.sh` forces the DKMS install over it, but confirm the right module won:

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

**Raw capture through V4L2 works with stock Raspberry Pi OS.** `v4l2-ctl`,
`media-ctl` and GStreamer's `v4l2src` need nothing beyond the driver. If all you
want is raw frames, stop here.

**`rpicam-hello`, `rpicam-vid`, `rpicam-still` and Picamera2 need our libcamera
fork.** Raspberry Pi's libcamera refuses any sensor it has no CamHelper for, and
upstream has none for the imx294, imx565, imx568, imx585, imx678 or ox08b40.
Even imx477, which upstream does know, needs the fork: every driver here reports
analogue gain in tenths of a dB rather than raw register codes, so an unpatched
helper drives the gain wrongly. It either pins the AGC at maximum or lands about
three times off, depending on the sensor.

The fork adds eight CamHelpers and the tuning files, on top of Raspberry Pi's
own libcamera:

    https://github.com/circuitvalley/libcamera-circuitvalley

Build it together with rpicam-apps, following Raspberry Pi's own build
instructions and substituting this repository for theirs. Prebuilt `.deb`
packages are planned so that this compile is not needed.

### What the fork replaces

The fork is Raspberry Pi's libcamera with two commits on top, and it installs
under `/usr/local`, so the distribution packages stay on disk. At runtime,
though, it takes precedence, and that changes two things for imx477:

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

