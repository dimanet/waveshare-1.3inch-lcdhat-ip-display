#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

WORKDIR=/opt/lcdhat
SERVICE=/etc/systemd/system/lcdhat-ips.service
BOOTCFG=/boot/firmware/config.txt
[[ -f /boot/config.txt && ! -f "$BOOTCFG" ]] && BOOTCFG=/boot/config.txt
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

log() {
  printf '[lcdhat] %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

for cmd in apt-get python3 systemctl wget 7z; do
  require_cmd "$cmd"
done

log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  p7zip-full \
  python3-pil \
  python3-numpy \
  python3-gpiozero \
  python3-spidev \
  fonts-dejavu-core \
  fonts-dejavu-mono

log "Enabling SPI and button pull-ups in $BOOTCFG"
python3 - "$BOOTCFG" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
out = []
have_spi = False
have_gpio = False
for line in lines:
    s = line.strip()
    if s == '#dtparam=spi=on':
        if not have_spi:
            out.append('dtparam=spi=on')
            have_spi = True
        continue
    if s == 'dtparam=spi=on':
        have_spi = True
    if s == 'gpio=6,19,5,26,13,21,20,16=pu':
        have_gpio = True
    out.append(line)
insert_at = next((i for i, l in enumerate(out) if l.strip() == '[all]'), len(out))
if not have_spi:
    out.insert(insert_at, 'dtparam=spi=on')
    insert_at += 1
if not have_gpio:
    out.insert(insert_at, 'gpio=6,19,5,26,13,21,20,16=pu')
p.write_text('\n'.join(out) + '\n')
PY

log "Downloading Waveshare demo package"
cd "$TMPDIR"
wget -O 1.3inch_LCD_HAT_code.7z https://files.waveshare.com/upload/b/bd/1.3inch_LCD_HAT_code.7z
7z x 1.3inch_LCD_HAT_code.7z -r -o./unpack >/dev/null
SRC_BASE=$(find "$TMPDIR/unpack" -type d -path '*/1.3inch_LCD_HAT_code/python' | head -n1)
if [[ -z "$SRC_BASE" ]]; then
  echo "Could not find Waveshare python demo files" >&2
  exit 1
fi

log "Installing display files"
mkdir -p "$WORKDIR"
install -m 0644 "$SRC_BASE/ST7789.py" "$WORKDIR/ST7789.py"
install -m 0644 "$SRC_BASE/config.py" "$WORKDIR/config.py"
cat > "$WORKDIR/show_ips.py" <<'PY'
#!/usr/bin/env python3
import os
import socket
import subprocess
import time
from PIL import Image, ImageDraw, ImageFont
import ST7789

WIDTH = 240
HEIGHT = 240
ROTATION = 90
REFRESH_SECONDS = 10
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
]


def pick_font(size):
    for font in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(font, size)
        except OSError:
            pass
    return ImageFont.load_default()


TITLE_FONT = pick_font(37)
TEXT_FONT = pick_font(28)
SMALL_FONT = pick_font(23)


def get_ipv4s():
    out = subprocess.check_output(["ip", "-o", "-4", "addr", "show", "up"], text=True)
    rows = []
    for line in out.splitlines():
        parts = line.split()
        ifname = parts[1]
        addr = parts[3].split("/", 1)[0]
        if ifname == "lo":
            continue
        rows.append((ifname, addr))
    return rows


def get_temp_c():
    candidates = [
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/devices/virtual/thermal/thermal_zone0/temp",
    ]
    for path in candidates:
        try:
            raw = open(path, "r", encoding="utf-8").read().strip()
            return float(raw) / 1000.0
        except Exception:
            pass
    try:
        out = subprocess.check_output(["vcgencmd", "measure_temp"], text=True).strip()
        return float(out.split("=")[1].split("'")[0])
    except Exception:
        return None


def render(disp):
    hostname = socket.gethostname()
    ipv4s = get_ipv4s()
    temp_c = get_temp_c()

    image = Image.new("RGB", (WIDTH, HEIGHT), "BLACK")
    draw = ImageDraw.Draw(image)

    draw.text((10, 8), hostname, font=TITLE_FONT, fill=(0, 220, 255))
    draw.line((10, 50, 230, 50), fill=(40, 40, 40), width=1)

    y = 60
    if ipv4s:
        for iface, addr in ipv4s[:4]:
            draw.text((10, y), iface.upper(), font=SMALL_FONT, fill=(255, 200, 0))
            y += 22
            draw.text((10, y), addr, font=TEXT_FONT, fill=(255, 255, 255))
            y += 34
            if y > 156:
                break
    else:
        draw.text((10, y), "No IPv4 address", font=TEXT_FONT, fill=(255, 120, 120))
        y += 34

    temp_text = f"CPU {temp_c:.1f} C" if temp_c is not None else "CPU temp n/a"
    draw.line((10, 184, 230, 184), fill=(40, 40, 40), width=1)
    draw.text((10, 192), temp_text, font=SMALL_FONT, fill=(120, 255, 120))
    draw.text((10, 216), time.strftime("%H:%M:%S"), font=SMALL_FONT, fill=(140, 140, 140))

    disp.ShowImage(image.rotate(ROTATION, expand=False))


def main():
    os.chdir("/opt/lcdhat")
    disp = ST7789.ST7789()
    disp.Init()
    disp.bl_DutyCycle(100)
    while True:
        render(disp)
        time.sleep(REFRESH_SECONDS)


if __name__ == "__main__":
    main()
PY
chmod 0755 "$WORKDIR/show_ips.py"

log "Installing systemd service"
cat > "$SERVICE" <<'UNIT'
[Unit]
Description=Waveshare 1.3inch LCD HAT IP display
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/lcdhat
ExecStart=/usr/bin/python3 /opt/lcdhat/show_ips.py
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable lcdhat-ips.service

log "Setup complete"
log "A reboot is required to bring up SPI cleanly."
log "After reboot, the LCD should show interface IPs rotated 90 degrees."
log "Reboot now with: reboot"
