# Waveshare 1.3inch LCD HAT IP Display

One-shot installer for Raspberry Pi + Waveshare 1.3inch LCD HAT.

It configures SPI, installs dependencies, and sets up a systemd service that shows:
- hostname
- IPv4 address(es)
- CPU temperature
- time

The display is rotated 90 degrees.

## Install

```bash
wget -O install-waveshare-1.3-lcd-ip-display.sh https://raw.githubusercontent.com/dimanet/waveshare-1.3inch-lcdhat-ip-display/main/install-waveshare-1.3-lcd-ip-display.sh
sudo bash install-waveshare-1.3-lcd-ip-display.sh
sudo reboot
```
