#!/usr/bin/bash
#
# DKMS build and install of the imx283 module alone.  ../setup.sh imx283 wraps this
# with the dependency, overlay and config.txt steps; run this one directly if
# you only want the module.

DRV_VERSION=0.0.1
DRV_IMX=imx283
SRC=/usr/src/${DRV_IMX}-${DRV_VERSION}

# Copy from this directory whatever the caller's working directory is.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

echo "Uninstalling any previous ${DRV_IMX} module"
# --all on a machine that has never installed this module prints a scary
# "not located in the DKMS tree" error.  Nothing is wrong; ignore it.
sudo dkms remove -m ${DRV_IMX} -v ${DRV_VERSION} --all >/dev/null 2>&1 || true

# Start from an empty source tree: a stale copy from an older package of the
# same name must not survive under ours.
sudo rm -rf "${SRC}"
sudo mkdir -p "${SRC}"
sudo cp -r ./* "${SRC}"

sudo dkms add -m ${DRV_IMX} -v ${DRV_VERSION} || exit 1
sudo dkms build -m ${DRV_IMX} -v ${DRV_VERSION} || exit 1
# --force: Raspberry Pi OS ships in-kernel imx477 and imx283 modules, and
# without it DKMS reports "installed" while placing no file, so the stock
# module keeps winning.  Harmless for the other sensors.
sudo dkms install --force -m ${DRV_IMX} -v ${DRV_VERSION} || exit 1
