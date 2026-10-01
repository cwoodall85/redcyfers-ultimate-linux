#!/bin/bash
# The book starts and enables wpa_supplicant for a placeholder interface
# (**EDITMEwlan0EDITME**). NetworkManager manages Wi-Fi on this desktop
# and starts wpa_supplicant itself, over D-Bus.
sed -i '/^systemctl \(start\|enable\) wpa_supplicant@\*\*EDITME/d' "$1"
