# IMX678 kernel driver

Installing and running the CircuitValley IMX678 driver on a Raspberry Pi.
The sensor is 3840 x 2160, 2 or 4 CSI-2 data lanes.

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
cd chc5_sensor_v4l2_drivers/imx678
./setup.sh
```

Add the overlay to `/boot/firmware/config.txt`, with camera autodetection off so
it does not fight the overlay:

```
camera_auto_detect=0
dtoverlay=imx678,cam0,always-on
```

Reboot.

`always-on` is currently needed on every module. Without it the camera regulator
stays off and the I2C bus reads back empty. Use `cam0` or `cam1` to match the
connector you plugged into.

## dtoverlay options

| Option | Effect |
| ------ | ------ |
| `cam0` | Camera is on the cam0 port instead of cam1 |
| `2lane` | Use 2 CSI-2 data lanes instead of 4 |
| `always-on` | Hold CAM_GPIO high so the module is never powered down |
| `mono` | Monochrome variant: advertise Y10/Y12 instead of Bayer |
| `hcg-level` | Gain, in tenths of a dB, at which the sensor switches to high conversion gain (default 26) |
| `rotation` | 0 or 180 |
| `orientation` | 0 = front, 1 = back, 2 = external |
| `media-controller` | Expose the full media graph (default on) |
| `link-frequency` | CSI-2 link frequency in Hz, see below |
| `clock-frequency` | INCK/XCLK frequency in Hz fitted on the module |

Options combine:

```
dtoverlay=imx678,cam0,always-on,link-frequency=445500000
```

### link-frequency

| Value | Mbps/lane | |
| ----- | --------- | - |
| 297000000 | 594 |  |
| 360000000 | 720 |  |
| 445500000 | 891 | default |
| 594000000 | 1188 |  |
| 720000000 | 1440 |  |
| 891000000 | 1782 |  |

1039500000 and 1188000000 appear in the register tables but the driver
**refuses** them. Those rows carry horizontal timing values that were later
retracted upstream after they produced broken low-signal frames, and the
corrected figures have never been validated on CircuitValley hardware.

### clock-frequency

CircuitValley IMX678 modules fit a **37.125 MHz** oscillator, which is the
default. The Raspberry Pi does **not** supply a clock to the camera. The
module oscillates itself, and `cam1_clk` in the device tree only *describes*
that crystal. Change this only if your board is fitted differently. The
driver supports 18 MHz, 24 MHz, 37.125 MHz and 72 MHz.

### Supplies

The driver asks the regulator core for `VANA`, `VDIG` and `VDDL`. Device-tree supply
lookup is **case-sensitive** and the overlay matches. A mismatch does not raise
an error: the core substitutes a dummy regulator and the sensor silently loses
its power sequencing.

## Checking it works

```bash
dmesg | grep -i imx678
media-ctl -p | grep -i imx678          # the sensor should appear as an entity
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

Tuning covers RP1 only, so libcamera support is Pi 5 and CM5 for now.

## Status and known gaps

Streams on a Raspberry Pi 5 through both V4L2 and libcamera, with autogain,
manual exposure and a three-lamp colour calibration completed.

- **The module tested has no IR-cut filter.** Patch saturation runs at 51 to 62
  per cent of reference and the colour matrices come out one and a half to two
  times stronger than the imx585's. Recapture the calibration if your module has
  a filter fitted.
- The driver advertises a continuous size range rather than a list of discrete
  modes, so libcamera collapses it to the single largest mode.

