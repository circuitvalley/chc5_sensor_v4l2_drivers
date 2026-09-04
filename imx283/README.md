# IMX283 kernel driver

Installing and running the CircuitValley IMX283 driver on a Raspberry Pi.
The sensor is 5472 x 3648, 4-lane only.

See the [repository README](../README.md) for the sensor overview, board
support and the libcamera setup that applies to every sensor here.

## Prerequisites

Kernel 6.12 or newer. Check with `uname -r`. The build refuses older kernels
rather than failing obscurely.

```bash
sudo apt install linux-headers-$(uname -r) dkms device-tree-compiler git
```

## Installation

```bash
git clone https://github.com/circuitvalley/chc5_sensor_v4l2_drivers
cd chc5_sensor_v4l2_drivers/imx283
./setup.sh
```

Add the overlay to `/boot/firmware/config.txt`, with camera autodetection off so
it does not fight the overlay:

```
camera_auto_detect=0
dtoverlay=imx283,cam0,always-on
```

Reboot.

`always-on` is currently needed on every module. Without it the camera regulator
stays off and the I2C bus reads back empty. Use `cam0` or `cam1` to match the
connector you plugged into.

## dtoverlay options

| Option | Effect |
| ------ | ------ |
| `cam0` | Camera is on the cam0 port instead of cam1 |
| `always-on` | Hold CAM_GPIO high so the module is never powered down |
| `rotation` | 0 or 180 |
| `orientation` | 0 = front, 1 = back, 2 = external |
| `link-frequency` | CSI-2 link frequency in Hz, see below |
| `clock-frequency` | INCK/XCLK frequency in Hz fitted on the module |

Options combine:

```
dtoverlay=imx283,cam0,always-on,link-frequency=360000000
```

### link-frequency

| Value | Mbps/lane | |
| ----- | --------- | - |
| 360000000 | 720 | default |
| 720000000 | 1440 |  |

### clock-frequency

CircuitValley IMX283 modules fit a **24 MHz** oscillator, which is the
default. The Raspberry Pi does **not** supply a clock to the camera. The
module oscillates itself, and `cam1_clk` in the device tree only *describes*
that crystal. Change this only if your board is fitted differently. The
driver supports 6 MHz, 18 MHz and 24 MHz.

### Supplies

The driver asks the regulator core for `VANA`, `VDIG` and `VDDL`. Device-tree supply
lookup is **case-sensitive** and the overlay matches. A mismatch does not raise
an error: the core substitutes a dummy regulator and the sensor silently loses
its power sequencing.

## Checking it works

```bash
dmesg | grep -i imx283
media-ctl -p | grep -i imx283          # the sensor should appear as an entity
v4l2-ctl --list-devices
```

## Capturing with V4L2

The RP1 camera front-end needs **both** the image and the embedded-data streams
running. Starting only the image node fails with `VIDIOC_STREAMON: Broken pipe`,
because the sensor's metadata link is enabled but has nowhere to go.

`/dev/mediaN` numbering is **not stable across boots**, so find the front-end by
model rather than hard-coding a number:

```bash
M=$(for m in /dev/media*; do media-ctl -d $m -p 2>/dev/null \
      | grep -q "model.*rp1-cfe" && { echo $m; break; }; done)

media-ctl -d $M -l '"csi2":4 -> "rp1-cfe-csi2_ch0":0 [1]'
media-ctl -d $M -l '"csi2":5 -> "rp1-cfe-embedded":0 [1]'
media-ctl -d $M -V '"SENSOR":0 [fmt:SBGGR12_1X12/WIDTHxHEIGHT]'
media-ctl -d $M -V '"csi2":4 [fmt:SBGGR12_1X12/WIDTHxHEIGHT]'
v4l2-ctl -d /dev/video0 --set-fmt-video=width=WIDTH,height=HEIGHT,pixelformat=pBCC

# both nodes at once
v4l2-ctl -d /dev/video1 --stream-mmap --stream-count=8 &
v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=8 --stream-to=frames.raw
```

Replace `SENSOR` with the entity name from `media-ctl -d $M -p`, and set the
width and height to a size this sensor advertises.

Only one process may own the sensor at a time, so stop `rpicam-hello` before
running any V4L2 capture.

## rpicam-apps and Picamera2

These need the CircuitValley libcamera fork, which carries the CamHelper and the
tuning file for this sensor. Raw V4L2 capture works without it. See
[libcamera and rpicam-apps](../README.md#libcamera-and-rpicam-apps) in the
repository README for what to install and what it replaces.

Tuning for this sensor exists upstream in libcamera for both RP1 and
unicam, but has never been exercised here because the module does not probe.

