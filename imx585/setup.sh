#!/usr/bin/bash

DRV_VERSION=0.0.1

DRV_IMX=imx585

echo "Uninstalling any previous ${DRV_IMX} module"
# --all on a machine that has never installed this module prints a scary
# "not located in the DKMS tree" error.  Nothing is wrong; ignore it.
sudo dkms remove -m ${DRV_IMX} -v ${DRV_VERSION} --all >/dev/null 2>&1 || true

sudo mkdir -p /usr/src/${DRV_IMX}-${DRV_VERSION}

sudo cp -r $(pwd)/* /usr/src/${DRV_IMX}-${DRV_VERSION}

sudo dkms add -m ${DRV_IMX} -v ${DRV_VERSION}
sudo dkms build -m ${DRV_IMX} -v ${DRV_VERSION}
sudo dkms install -m ${DRV_IMX} -v ${DRV_VERSION}
