#!/usr/bin/bash
#
# Install one CircuitValley sensor driver, or all of them.
#
#   ./setup.sh imx585
#   ./setup.sh --all
#
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENSORS=$(cd "$HERE" && ls -d */ 2>/dev/null | tr -d '/' | grep -vE '^(\.|tools)' | tr '\n' ' ')

usage() {
	cat <<USAGE
Usage: ./setup.sh <sensor> | --all

Available sensors: ${SENSORS}

After installing, add the overlay to /boot/firmware/config.txt:

    camera_auto_detect=0
    dtoverlay=<sensor>

See <sensor>/README.md for the dtoverlay options.
USAGE
}

install_one() {
	local s="$1"
	if [ ! -d "$HERE/$s" ]; then
		echo "No such sensor: $s" >&2
		echo "Available: ${SENSORS}" >&2
		return 2
	fi
	echo "=== installing $s"
	( cd "$HERE/$s" && ./setup.sh ) || return $?
}

[ "$#" -eq 1 ] || { usage >&2; exit 2; }

case "$1" in
	-h|--help) usage; exit 0 ;;
	--all)
		rc=0
		for s in $SENSORS; do install_one "$s" || rc=$?; done
		exit $rc
		;;
	*) install_one "$1"; exit $? ;;
esac
