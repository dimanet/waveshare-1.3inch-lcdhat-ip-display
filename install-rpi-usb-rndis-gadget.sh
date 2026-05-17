#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

USB_IP_CIDR=10.99.99.1/24
SERIAL=${SERIAL:-krjakrja0001}
MANUFACTURER=${MANUFACTURER:-krjakrja bot}
PRODUCT=${PRODUCT:-Pi Zero 2 W USB RNDIS}
BOOTCFG=/boot/firmware/config.txt
CMDLINE=/boot/firmware/cmdline.txt
[[ -f /boot/config.txt && ! -f "$BOOTCFG" ]] && BOOTCFG=/boot/config.txt
[[ -f /boot/cmdline.txt && ! -f "$CMDLINE" ]] && CMDLINE=/boot/cmdline.txt

log() {
  printf '[usb-rndis] %s\n' "$*"
}

backup_file() {
  local file=$1
  [[ -f "$file" ]] || return 0
  cp -a "$file" "$file.bak.$(date +%Y%m%d%H%M%S)"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

for cmd in python3 systemctl modprobe ip; do
  require_cmd "$cmd"
done

log "Backing up boot files"
backup_file "$BOOTCFG"
backup_file "$CMDLINE"

log "Ensuring dwc2 overlay and boot module load"
python3 - "$BOOTCFG" "$CMDLINE" <<'PY'
from pathlib import Path
import sys
bootcfg = Path(sys.argv[1])
cmdline = Path(sys.argv[2])

cfg_lines = bootcfg.read_text().splitlines()
out = []
have_dwc2 = False
for line in cfg_lines:
    if line.strip() == 'dtoverlay=dwc2':
        have_dwc2 = True
    out.append(line)
if not have_dwc2:
    insert_at = next((i for i, l in enumerate(out) if l.strip() == '[all]'), len(out))
    out.insert(insert_at + (1 if insert_at < len(out) else 0), 'dtoverlay=dwc2')
bootcfg.write_text('\n'.join(out) + '\n')

cmd = cmdline.read_text().strip()
parts = cmd.split()
parts = [p for p in parts if p not in ('modules-load=dwc2,g_ether', 'modules-load=dwc2')]
insert_at = parts.index('rootwait') + 1 if 'rootwait' in parts else len(parts)
parts.insert(insert_at, 'modules-load=dwc2')
cmdline.write_text(' '.join(parts) + '\n')
PY

log "Installing RNDIS gadget helper"
install -d /usr/local/sbin
cat > /usr/local/sbin/usb-rndis-gadget <<'SH'
#!/usr/bin/env bash
set -euo pipefail

USB_IP_CIDR=10.99.99.1/24
SERIAL=${SERIAL:-krjakrja0001}
MANUFACTURER=${MANUFACTURER:-krjakrja bot}
PRODUCT=${PRODUCT:-Pi Zero 2 W USB RNDIS}
G=/sys/kernel/config/usb_gadget/rpi_usb
UDC=$(ls /sys/class/udc | head -n1)

modprobe libcomposite
mkdir -p /sys/kernel/config/usb_gadget
mkdir -p "$G"
cd "$G"

echo 0x0525 > idVendor
echo 0xa4a2 > idProduct
echo 0x0200 > bcdUSB
echo 0x0100 > bcdDevice
echo 0xEF > bDeviceClass
echo 0x04 > bDeviceSubClass
echo 0x01 > bDeviceProtocol

mkdir -p strings/0x409
echo "$SERIAL" > strings/0x409/serialnumber
echo "$MANUFACTURER" > strings/0x409/manufacturer
echo "$PRODUCT" > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo RNDIS > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

mkdir -p functions/rndis.usb0
echo 02:12:34:56:78:9a > functions/rndis.usb0/dev_addr
echo 02:98:76:54:32:10 > functions/rndis.usb0/host_addr

echo 1 > os_desc/use
echo 0xcd > os_desc/b_vendor_code
echo MSFT100 > os_desc/qw_sign
mkdir -p functions/rndis.usb0/os_desc/interface.rndis
echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

ln -sfn functions/rndis.usb0 configs/c.1/rndis.usb0
ln -sfn configs/c.1 os_desc/c.1

echo "$UDC" > UDC

ip link set usb0 up
ip address replace "$USB_IP_CIDR" dev usb0
SH
chmod 755 /usr/local/sbin/usb-rndis-gadget

cat > /usr/local/sbin/usb-rndis-gadget-cleanup <<'SH'
#!/usr/bin/env bash
set -euo pipefail
G=/sys/kernel/config/usb_gadget/rpi_usb
if [[ -d "$G" ]]; then
  ip link set usb0 down 2>/dev/null || true
  ip address flush dev usb0 2>/dev/null || true
  cd "$G"
  echo '' > UDC 2>/dev/null || true
  rm -f os_desc/c.1 || true
  rm -f configs/c.1/rndis.usb0 || true
  rmdir functions/rndis.usb0/os_desc/interface.rndis 2>/dev/null || true
  rmdir functions/rndis.usb0/os_desc 2>/dev/null || true
  rmdir functions/rndis.usb0 2>/dev/null || true
  rmdir configs/c.1/strings/0x409 2>/dev/null || true
  rmdir configs/c.1 2>/dev/null || true
  rmdir strings/0x409 2>/dev/null || true
  cd /
  rmdir "$G" 2>/dev/null || true
fi
SH
chmod 755 /usr/local/sbin/usb-rndis-gadget-cleanup

log "Installing systemd service"
cat > /etc/systemd/system/usb-rndis-gadget.service <<UNIT
[Unit]
Description=USB RNDIS gadget for Windows hosts
DefaultDependencies=no
Requires=sys-kernel-config.mount
After=sys-kernel-config.mount systemd-modules-load.service
Before=network-pre.target NetworkManager.service
Wants=network-pre.target
ConditionPathExists=/sys/kernel/config

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="USB_IP_CIDR=10.99.99.1/24"
Environment="SERIAL=$SERIAL"
Environment="MANUFACTURER=$MANUFACTURER"
Environment="PRODUCT=$PRODUCT"
ExecStart=/usr/local/sbin/usb-rndis-gadget
ExecStop=/usr/local/sbin/usb-rndis-gadget-cleanup

[Install]
WantedBy=sysinit.target
UNIT

systemctl daemon-reload
systemctl enable usb-rndis-gadget.service

log "Done. Reboot required."
log "After reboot, plug the Pi into the data/OTG USB port and it will expose usb0 as $USB_IP_CIDR with no gateway or DNS."
log "Reboot now with: reboot"
