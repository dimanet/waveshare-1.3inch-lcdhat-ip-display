# Waveshare 1.3inch LCD HAT IP Display

One-shot installer for Raspberry Pi + Waveshare 1.3inch LCD HAT.

It configures SPI, installs dependencies, and sets up a systemd service that shows:
- hostname
- IPv4 address(es)
- CPU temperature
- time

The display is rotated 90 degrees.

## USB gadget installer

This repo also includes a one-shot Raspberry Pi USB RNDIS gadget installer.

It configures a Pi Zero 2 W style USB gadget that exposes:
- `usb0`
- fixed IP `10.99.99.1/24`
- no gateway
- no DNS
- Windows-friendly RNDIS descriptors

### One-liner for a fresh Pi

```bash
curl -fsSL https://raw.githubusercontent.com/dimanet/waveshare-1.3inch-lcdhat-ip-display/main/install-rpi-usb-rndis-gadget.sh | sudo bash && sudo reboot
```

Use the Pi's **data/OTG USB port**, not the power-only port.

## LCD installer

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/dimanet/waveshare-1.3inch-lcdhat-ip-display/main/install-waveshare-1.3-lcd-ip-display.sh | sudo bash
sudo reboot
```

### Download then run

```bash
wget -O install-waveshare-1.3-lcd-ip-display.sh https://raw.githubusercontent.com/dimanet/waveshare-1.3inch-lcdhat-ip-display/main/install-waveshare-1.3-lcd-ip-display.sh
sudo bash install-waveshare-1.3-lcd-ip-display.sh
sudo reboot
```
