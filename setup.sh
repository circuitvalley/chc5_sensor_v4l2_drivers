#!/usr/bin/bash
#
# Install a CircuitValley sensor driver on a Raspberry Pi.
#
# One command does the whole job: build dependencies, DKMS module, device-tree
# overlay and the config.txt entry.  Reboot afterwards.
#
#   sudo ./setup.sh imx585                        # Pi 5: connector cam0
#   sudo ./setup.sh imx585 --cam1 --mono
#   sudo ./setup.sh imx477 --link-frequency 540000000
#   sudo ./setup.sh --all                         # every module, no config.txt entry
#   sudo ./setup.sh --check imx585                # verify an install, before or after reboot
#   sudo ./setup.sh --uninstall imx585
#
# <sensor>/setup.sh is the module-only step and is what this script calls for
# the DKMS part; it still works on its own.
#
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=0.0.1                  # PACKAGE_VERSION in every dkms.conf
BEGIN='# >>> circuitvalley sensor >>>'
END='# <<< circuitvalley sensor <<<'
DISABLED_NOTE='# disabled by circuitvalley setup.sh'

# Test hooks.  SETUP_CONFIG=<file> edits that file instead of the boot config;
# SETUP_MODEL=<string> overrides the board model; SETUP_KVER=<version> the
# running kernel; --dry-run prints the privileged commands instead of running
# them.
DRY_RUN=${DRY_RUN:-}

info() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run()  { info "+ $*"; [ -n "$DRY_RUN" ] || "$@"; }

usage() {
	cat <<USAGE
Usage: sudo ./setup.sh <sensor> [options]
       sudo ./setup.sh --all [--no-deps]
       sudo ./setup.sh --check [<sensor>]
       sudo ./setup.sh --uninstall <sensor>

Sensors: $(list_sensors | paste -sd' ')

Options for a single sensor:
  --cam0 | --cam1        camera connector (default: cam0 on Pi 5 / CM5, cam1 on Pi 4 / CM4)
  --2lane                use 2 data lanes (automatic on a Pi 4)
  --mono                 monochrome module (imx585, imx678)
  --link-frequency HZ    CSI-2 link frequency, see <sensor>/README.md for the accepted values
  --option NAME[=VALUE]  any other overlay parameter, repeatable (e.g. --option rotation=180)
  --config-only          only (re)write the config.txt entry, skip the build
  --no-config            build and install the module, leave config.txt alone
  --no-deps              do not apt-get anything
  --dry-run              show what would be done

Installs: build dependencies, the DKMS module (rebuilt automatically on kernel
upgrades), the overlay in the firmware directory, and a managed block in
config.txt:  $BEGIN ... $END
Re-running replaces that block and touches nothing else in the file.
USAGE
}

# Every directory that carries a DKMS package is a sensor.
list_sensors() {
	local d
	for d in "$HERE"/*/; do
		d=${d%/}
		[ -f "$d/setup.sh" ] && [ -f "$d/dkms.conf" ] && basename "$d"
	done
}

# overlay_has <sensor> <parameter>: does the overlay accept this dtoverlay parameter?
overlay_has() {
	grep -qE "^[[:space:]]*$2[[:space:]]*=" "$HERE/$1/$1-overlay.dts"
}

detect_board() {
	MODEL=${SETUP_MODEL:-$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')}
	LANES=4; DEFAULT_PORT=cam0; SINGLE_PORT=
	case "$MODEL" in
		"Raspberry Pi 4 Model B"*|"Raspberry Pi 400"*)
			LANES=2; DEFAULT_PORT=cam1; SINGLE_PORT=cam1 ;;
		"Raspberry Pi Compute Module 4"*)
			DEFAULT_PORT=cam1 ;;          # CAM1 has 4 lanes, CAM0 only 2
		"Raspberry Pi 5"*|"Raspberry Pi Compute Module 5"*)
			;;
		"")
			warn "cannot read /proc/device-tree/model; assuming a 4-lane connector" ;;
		*)
			warn "untested board '$MODEL'; assuming a 4-lane connector" ;;
	esac
	[ -n "$MODEL" ] && info "board: $MODEL"
}

check_kernel() {
	KVER=${SETUP_KVER:-$(uname -r)}
	local maj=${KVER%%.*} rest=${KVER#*.} min
	min=${rest%%[!0-9]*}
	if [ "$maj" -lt 6 ] || { [ "$maj" -eq 6 ] && [ "$min" -lt 12 ]; }; then
		die "kernel $KVER is too old: this package needs 6.12 or newer" \
		    "(sudo apt full-upgrade, reboot, re-run)"
	fi
	info "kernel: $KVER"
}

# The meta package that tracks kernel upgrades first (6.12.34+rpt-rpi-2712 ->
# linux-headers-rpi-2712), so DKMS can rebuild after the next apt full-upgrade;
# the exact package as the fallback.
headers_candidates() {
	case "$KVER" in
		*+rpt-*) echo "linux-headers-${KVER##*+rpt-}" ;;
	esac
	echo "linux-headers-$KVER"
}

install_deps() {
	local pkgs=() p h
	command -v dkms >/dev/null || pkgs+=(dkms)
	command -v dtc  >/dev/null || pkgs+=(device-tree-compiler)
	{ command -v make >/dev/null && command -v gcc >/dev/null; } || pkgs+=(build-essential)
	[ -d "/lib/modules/$KVER/build" ] || pkgs+=(HEADERS)
	if [ ${#pkgs[@]} -eq 0 ]; then
		info "dependencies: present"
		return 0
	fi
	[ -n "$NO_DEPS" ] && die "missing dependencies: ${pkgs[*]} (drop --no-deps, or install them)"
	run apt-get update
	for p in "${pkgs[@]}"; do
		if [ "$p" = HEADERS ]; then
			for h in $(headers_candidates); do
				run apt-get install -y "$h" || true
				[ -d "/lib/modules/$KVER/build" ] && break
			done
		else
			run apt-get install -y "$p" || die "could not install $p"
		fi
	done
	[ -n "$DRY_RUN" ] && return 0
	[ -d "/lib/modules/$KVER/build" ] ||
		die "no kernel headers for the running kernel $KVER." \
		    "The repository only carries headers for a newer kernel:" \
		    "run 'sudo apt full-upgrade', reboot, then re-run this script."
}

# Where the firmware reads overlays and config.txt: /boot/firmware on Bookworm
# and later, /boot on older images.
locate_boot() {
	OVL_DIR=/boot/overlays
	[ -d /boot/firmware/overlays ] && OVL_DIR=/boot/firmware/overlays
	CFG=${SETUP_CONFIG:-/boot/firmware/config.txt}
	[ -f "$CFG" ] || CFG=/boot/config.txt
	[ -f "$CFG" ] || CFG=
}

require_config() {
	[ -n "$CFG" ] || die "no config.txt found under /boot/firmware or /boot"
}

# Another DKMS package building the same module name (will127534's, or an
# older one of ours) gets rebuilt on every kernel upgrade too, and whichever
# installs last wins.  Point at it; do not delete someone else's package.
warn_other_dkms() {
	local s=$1 conf name ver
	for conf in /usr/src/*/dkms.conf; do
		[ -f "$conf" ] || continue
		[ "$conf" = "/usr/src/$s-$VERSION/dkms.conf" ] && continue
		grep -qE "^BUILT_MODULE_NAME(\[[0-9]+\])?=\"?$s\"?[[:space:]]*$" "$conf" || continue
		name=$(sed -n 's/^PACKAGE_NAME=//p' "$conf" | tr -d '"')
		ver=$(sed -n 's/^PACKAGE_VERSION=//p' "$conf" | tr -d '"')
		warn "another DKMS package also builds $s: ${conf%/dkms.conf}." \
		     "Both are rebuilt on every kernel upgrade and the last one installed wins." \
		     "Remove it with: sudo dkms remove -m $name -v $ver --all"
	done
}

install_module() {
	local s=$1 src mod
	src="/usr/src/$s-$VERSION"
	# Keep the distribution's overlay of the same name (imx477, imx283) so
	# --uninstall can put it back.
	if [ -f "$OVL_DIR/$s.dtbo" ] && [ ! -f "$OVL_DIR/$s.dtbo.orig" ]; then
		run cp "$OVL_DIR/$s.dtbo" "$OVL_DIR/$s.dtbo.orig"
	fi
	info "=== $s: DKMS build and install"
	run "$HERE/$s/setup.sh" || { warn "$s: DKMS install failed"; return 1; }
	[ -n "$DRY_RUN" ] && return 0

	# Raspberry Pi OS ships in-kernel imx477 and imx283 modules; make sure ours won.
	mod=$(modinfo -n "$s" 2>/dev/null || true)
	case "$mod" in
		*/updates/dkms/*) info "$s: module $mod" ;;
		"")  warn "$s: module not found after the install"; return 1 ;;
		*)   warn "$s: the in-kernel module still wins ($mod);" \
		          "run: sudo dkms install --force -m $s -v $VERSION"; return 1 ;;
	esac

	# The DKMS hook compiles the overlay and copies it to /boot/overlays.  Make
	# sure it reached the directory the firmware actually reads.
	[ -f "$src/$s.dtbo" ] || { warn "$s: the overlay was not compiled (is dtc installed?)"; return 1; }
	if ! cmp -s "$src/$s.dtbo" "$OVL_DIR/$s.dtbo"; then
		run install -m 644 "$src/$s.dtbo" "$OVL_DIR/$s.dtbo"
	fi
	info "$s: overlay $OVL_DIR/$s.dtbo"
	warn_other_dkms "$s"
}

overlay_line() {
	local s=$1 line
	line="dtoverlay=$s,$PORT,always-on"
	[ -n "$TWO_LANE" ]  && line="$line,2lane"
	[ -n "$MONO" ]      && line="$line,mono"
	[ -n "$LINK_FREQ" ] && line="$line,link-frequency=$LINK_FREQ"
	[ -n "$EXTRA" ]     && line="$line,$EXTRA"
	printf '%s\n' "$line"
}

strip_block() {   # strip_block <in> <out>: the file without our managed block
	awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$1" > "$2"
}

commit_config() {   # commit_config <tmp>: install <tmp> as the boot config, with a backup
	if [ -n "$DRY_RUN" ] && [ -z "${SETUP_CONFIG:-}" ]; then
		info "+ (would write $CFG)"
		rm -f "$1"
		return 0
	fi
	local stamp="$CFG.bak.$(date +%Y%m%d-%H%M%S)" bak n=1
	bak=$stamp
	while [ -e "$bak" ]; do bak="$stamp.$n"; n=$((n+1)); done
	cp "$CFG" "$bak"
	install -m 644 "$1" "$CFG"
	rm -f "$1"
	info "config.txt: $CFG updated (backup kept beside it)"
}

write_config() {
	local s=$1 tmp line pat others
	require_config
	line=$(overlay_line "$s")
	tmp=$(mktemp)
	# 1. a previous block of ours goes; nothing else is touched
	strip_block "$CFG" "$tmp"
	# 2. the stock image enables camera autodetection, which fights the overlay
	sed -i "s|^camera_auto_detect=1[[:space:]]*\$|#& $DISABLED_NOTE|" "$tmp"
	# 3. a sensor overlay outside our block would collide on the I2C address
	pat="^dtoverlay=($(list_sensors | paste -sd'|'))([,[:space:]]|\$)"
	others=$(grep -nE "$pat" "$tmp" || true)
	[ -n "$others" ] && warn "config.txt already has a sensor overlay outside the managed block;" \
	                         "remove it unless it is intended:"$'\n'"$others"
	# 4. our block, under [all] so a preceding [pi4]/[cm4] filter cannot swallow it
	printf '\n%s\n[all]\ncamera_auto_detect=0\n%s\n%s\n' "$BEGIN" "$line" "$END" >> "$tmp"
	info "config.txt entry: $line"
	commit_config "$tmp"
}

# Remove our block, but only if it is this sensor's.  Put camera autodetection
# back only where this script disabled it.
remove_config() {
	local s=$1 tmp
	require_config
	if ! awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$CFG" |
			grep -qE "^dtoverlay=$s([,[:space:]]|\$)"; then
		info "config.txt: no managed entry for $s"
		return 0
	fi
	tmp=$(mktemp)
	strip_block "$CFG" "$tmp"
	sed -i "s|^#camera_auto_detect=1 $DISABLED_NOTE\$|camera_auto_detect=1|" "$tmp"
	info "config.txt: removing the managed entry for $s"
	commit_config "$tmp"
}

check_sensor() {
	local s=$1 rc=0 mod bound
	info "=== $s"
	if dkms status -m "$s" -v "$VERSION" 2>/dev/null | grep -q ': installed'; then
		info "  dkms:      installed"
	else
		info "  dkms:      NOT installed"; rc=1
	fi
	mod=$(modinfo -n "$s" 2>/dev/null || true)
	case "$mod" in
		*/updates/dkms/*) info "  module:    $mod" ;;
		"")  info "  module:    not found"; rc=1 ;;
		*)   info "  module:    STOCK module wins: $mod"; rc=1 ;;
	esac
	if [ -f "$OVL_DIR/$s.dtbo" ]; then
		if cmp -s "$OVL_DIR/$s.dtbo" "/usr/src/$s-$VERSION/$s.dtbo" 2>/dev/null; then
			info "  overlay:   $OVL_DIR/$s.dtbo"
		else
			info "  overlay:   $OVL_DIR/$s.dtbo differs from the package copy (replaced by an OS update?)"; rc=1
		fi
	else
		info "  overlay:   MISSING $OVL_DIR/$s.dtbo"; rc=1
	fi
	if [ -z "$CFG" ]; then
		info "  config:    no config.txt found"; rc=1
	elif grep -qE "^dtoverlay=$s([,[:space:]]|\$)" "$CFG"; then
		info "  config:    $(grep -E "^dtoverlay=$s([,[:space:]]|\$)" "$CFG" | head -1)"
	else
		info "  config:    no dtoverlay=$s line in $CFG"; rc=1
	fi
	if lsmod | grep -qE "^$s[[:space:]]"; then
		info "  loaded:    yes"
	else
		info "  loaded:    no (reboot after installing)"
	fi
	bound=$(find "/sys/bus/i2c/drivers/$s" -maxdepth 1 -name '[0-9]*-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]' \
	             -printf '%f ' 2>/dev/null || true)
	if [ -n "$bound" ]; then
		info "  probed:    yes ($bound)"
	else
		info "  probed:    no (after a reboot, check: dmesg | grep -i $s)"
	fi
	return $rc
}

uninstall_sensor() {
	local s=$1
	info "=== $s: uninstall"
	run dkms remove -m "$s" -v "$VERSION" --all || true
	run rm -rf "/usr/src/$s-$VERSION"
	if [ -f "$OVL_DIR/$s.dtbo.orig" ]; then
		run mv "$OVL_DIR/$s.dtbo.orig" "$OVL_DIR/$s.dtbo"    # the distribution's own overlay
	else
		run rm -f "$OVL_DIR/$s.dtbo"
	fi
	# the DKMS hook's copy, when /boot/overlays is a directory of its own
	if [ "$OVL_DIR" != /boot/overlays ] && [ -d /boot/overlays ] && [ ! -L /boot/overlays ]; then
		run rm -f "/boot/overlays/$s.dtbo"
	fi
	remove_config "$s"
}

finish() {
	local s=$1
	cat <<DONE

Done.  Reboot to load the driver:      sudo reboot
Then verify:                           sudo ./setup.sh --check $s

Raw capture works as is (v4l2-ctl, media-ctl, GStreamer v4l2src).
rpicam-apps and Picamera2 need the CircuitValley libcamera fork; see
README.md, section "libcamera and rpicam-apps".
DONE
}

# ---------------------------------------------------------------- arguments

MODE=install SENSOR= PORT= TWO_LANE= MONO= LINK_FREQ= EXTRA=
NO_DEPS= NO_CONFIG= CONFIG_ONLY=
ORIG_ARGS=("$@")
for a in "$@"; do
	case "$a" in -h|--help) usage; exit 0 ;; esac
done
while [ $# -gt 0 ]; do
	case "$1" in
		--all)             MODE=all ;;
		--check)           MODE=check ;;
		--uninstall)       MODE=uninstall ;;
		--config-only)     CONFIG_ONLY=1 ;;
		--cam0)            PORT=cam0 ;;
		--cam1)            PORT=cam1 ;;
		--2lane)           TWO_LANE=1 ;;
		--mono)            MONO=1 ;;
		--link-frequency)  [ $# -ge 2 ] || die "--link-frequency needs a value in Hz"; LINK_FREQ=$2; shift ;;
		--link-frequency=*) LINK_FREQ=${1#*=} ;;
		--option)          [ $# -ge 2 ] || die "--option needs NAME[=VALUE]"; EXTRA=${EXTRA:+$EXTRA,}$2; shift ;;
		--option=*)        EXTRA=${EXTRA:+$EXTRA,}${1#*=} ;;
		--no-deps)         NO_DEPS=1 ;;
		--no-config)       NO_CONFIG=1 ;;
		--dry-run)         DRY_RUN=1 ;;
		-*)                die "unknown option $1 (try --help)" ;;
		*)                 [ -z "$SENSOR" ] || die "one sensor at a time, or --all"; SENSOR=$1 ;;
	esac
	shift
done

if [ "$MODE" = all ]; then
	[ -z "$SENSOR" ] || die "--all takes no sensor name"
else
	[ -n "$SENSOR" ] || [ "$MODE" = check ] || die "which sensor? (try --help)"
	if [ -n "$SENSOR" ] && ! { [ -d "$HERE/$SENSOR" ] && [ -f "$HERE/$SENSOR/dkms.conf" ]; }; then
		die "no such sensor: $SENSOR (have: $(list_sensors | paste -sd' '))"
	fi
fi
case "$LINK_FREQ" in ''|*[!0-9]*) [ -z "$LINK_FREQ" ] || die "--link-frequency wants a number in Hz" ;; esac

# Everything but --check and --dry-run changes the system: become root.
if [ "$(id -u)" -ne 0 ] && [ "$MODE" != check ] && [ -z "$DRY_RUN" ] && [ -z "${SETUP_CONFIG:-}" ]; then
	command -v sudo >/dev/null || die "run this script as root"
	exec sudo "$0" "${ORIG_ARGS[@]}"
fi


locate_boot

# ---------------------------------------------------------------- modes

case "$MODE" in
check)
	rc=0
	for s in ${SENSOR:-$(list_sensors)}; do
		check_sensor "$s" || rc=1
	done
	exit $rc
	;;
uninstall)
	uninstall_sensor "$SENSOR"
	info "Reboot to unload the driver."
	exit 0
	;;
all)
	detect_board
	check_kernel
	[ -n "$NO_DEPS" ] || install_deps
	rc=0
	for s in $(list_sensors); do
		install_module "$s" || rc=1
		if [ "$LANES" = 2 ] && ! overlay_has "$s" 2lane; then
			info "$s: installed, but it has no 2-lane mode and will not stream on this board"
		fi
	done
	info
	info "All modules installed.  No config.txt entry was written: pick the sensor with"
	info "    sudo ./setup.sh <sensor> --config-only [--cam0|--cam1] [options]"
	info "then reboot."
	exit $rc
	;;
esac

# ---------------------------------------------------------------- one sensor

detect_board

PORT=${PORT:-$DEFAULT_PORT}
if [ -n "$SINGLE_PORT" ] && [ "$PORT" != "$SINGLE_PORT" ]; then
	die "this board has one camera connector, $SINGLE_PORT"
fi
case "$MODEL" in
	"Raspberry Pi Compute Module 4"*) [ "$PORT" = cam0 ] && { LANES=2; info "CM4 CAM0 has 2 data lanes"; } ;;
esac
if [ "$LANES" = 2 ] && [ -z "$TWO_LANE" ]; then
	TWO_LANE=1
	info "2-lane connector: adding 2lane"
fi
if [ -n "$TWO_LANE" ] && ! overlay_has "$SENSOR" 2lane; then
	die "$SENSOR has no 2-lane mode; it needs a 4-lane connector (Pi 5, CM4 or CM5 carrier)"
fi
if [ -n "$MONO" ] && ! overlay_has "$SENSOR" mono; then
	die "$SENSOR has no mono variant"
fi
# The RP1 receiver on a Pi 5 receives nothing at the imx294's 480 MHz default;
# 600 MHz is the rate proven on the bench.  See imx294/README.md.
if [ -z "$LINK_FREQ" ] && [ "$SENSOR" = imx294 ]; then
	LINK_FREQ=600000000
	info "imx294: link-frequency=$LINK_FREQ (the 480 MHz default does not stream on a Pi 5)"
fi
info "camera port: $PORT"

if [ -n "$CONFIG_ONLY" ]; then
	write_config "$SENSOR"
	finish "$SENSOR"
	exit 0
fi

check_kernel
[ -n "$NO_DEPS" ] || install_deps
install_module "$SENSOR" || die "$SENSOR: install failed, config.txt left untouched"
if [ -n "$NO_CONFIG" ]; then
	info "config.txt left alone (--no-config).  The entry would have been:"
	info "    $(overlay_line "$SENSOR")"
else
	write_config "$SENSOR"
fi
finish "$SENSOR"
