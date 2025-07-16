#!/bin/bash
set -e

TILL_URL="https://aceofvapez.retail.lightspeed.app/"
CHROME_DESKTOP=/etc/xdg/autostart/taov-chrome.desktop
SIMPLEPOSPRINT_DIR=/opt/SimplePOSPrint
WALLPAPER_SRC="$PWD/TAOV-Wallpaper.jpg"
WALLPAPER_DST="/usr/share/lubuntu/wallpapers/TAOV-Wallpaper.jpg"
SPLASH_SRC="$PWD/logo-letterhead-white.png"
SPLASH_DST="/usr/share/plymouth/themes/taov-logo.png"
THIS_USER="${SUDO_USER:-$USER}"

echo "==== TAOV Till Setup Script ===="

echo "[1/13] Updating system..."
sudo apt update && sudo apt upgrade -y

echo "[2/13] Installing essentials (CUPS, samba, python, etc)..."
sudo apt install -y curl wget gnupg lsb-release cups \
  python3 python3-pip python3-venv git unzip samba

echo "[3/13] Installing Google Chrome..."
wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i /tmp/chrome.deb || sudo apt-get install -f -y

echo "[4/13] Installing AnyDesk..."
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | sudo apt-key add -
echo "deb http://deb.anydesk.com/ all main" | sudo tee /etc/apt/sources.list.d/anydesk.list
sudo apt update
sudo apt install -y anydesk

echo "[5/13] Enabling AnyDesk to start at boot..."
sudo systemctl enable anydesk --now

echo "[6/13] Enabling CUPS for printing..."
sudo systemctl enable --now cups

echo "[7/13] Setting up Samba open share..."
sudo mkdir -p /srv/intray
sudo chmod 777 /srv/intray
if ! grep -q "\[intray\]" /etc/samba/smb.conf; then
  sudo bash -c 'cat >>/etc/samba/smb.conf <<EOF

[intray]
   path = /srv/intray
   browseable = yes
   guest ok = yes
   read only = no
   force user = nobody
EOF'
fi
sudo systemctl restart smbd nmbd

echo "[8/13] Allowing Samba and SimplePOSPrint through firewall (if ufw is present)..."
if command -v ufw &> /dev/null; then
  sudo ufw allow samba || true
  sudo ufw allow 5000/tcp || true
  sudo ufw enable || true
else
  echo "ufw firewall not installed, skipping firewall step."
fi

echo "[9/13] Cloning SimplePOSPrint repo..."
if [ ! -d "$SIMPLEPOSPRINT_DIR" ]; then
  sudo git clone https://github.com/Mike-TOAV/SimplePOSPrint.git "$SIMPLEPOSPRINT_DIR"
  sudo chown -R $THIS_USER:$THIS_USER "$SIMPLEPOSPRINT_DIR"
else
  echo "SimplePOSPrint directory already exists, skipping clone."
fi

cd "$SIMPLEPOSPRINT_DIR"
echo "[10/13] Running SimplePOSPrint installer..."
sudo -u $THIS_USER bash ./install.sh

echo "[11/13] Setting Chrome to autostart in kiosk mode..."
cat <<EOF | sudo tee $CHROME_DESKTOP
[Desktop Entry]
Type=Application
Name=TAOV Till Chrome
Exec=google-chrome --kiosk --start-maximized "$TILL_URL" "https://intranet.taov.webhop.me" "http://localhost:5000/"
X-GNOME-Autostart-enabled=true
NoDisplay=false
EOF
sudo chmod 644 $CHROME_DESKTOP

echo "[12/13] Setting custom wallpaper (if file present and running LXQt/Lubuntu)..."
if [ -f "$WALLPAPER_SRC" ]; then
  sudo mkdir -p "$(dirname "$WALLPAPER_DST")"
  sudo cp "$WALLPAPER_SRC" "$WALLPAPER_DST"
  su -l $THIS_USER -c "pcmanfm-qt --set-wallpaper=$WALLPAPER_DST" || true
  echo "Wallpaper set to $WALLPAPER_DST"
else
  echo "No wallpaper file found at $WALLPAPER_SRC; skipping."
fi

echo "[13/13] Setting custom splash logo (plymouth, optional)..."
if [ -f "$SPLASH_SRC" ]; then
  sudo mkdir -p "$(dirname "$SPLASH_DST")"
  sudo cp "$SPLASH_SRC" "$SPLASH_DST"
  echo "Custom splash logo placed at $SPLASH_DST"
  echo "To use as Plymouth splash, manual theme config may be needed (see README for details)."
else
  echo "No splash logo found at $SPLASH_SRC; skipping."
fi

echo
echo "==== DONE ===="
echo "On next reboot:"
echo "  - Chrome will launch in kiosk mode to $TILL_URL"
echo "  - Samba share 'intray' is open to the network."
echo "  - SimplePOSPrint is installed and running as a service."
echo "  - AnyDesk remote support is installed and running."
echo "  - Wallpaper and splash set if images provided."
echo
echo "To install Chrome plugins/extensions (SimplePOSPrint):"
echo "  1. Open Chrome (it will auto-start, press Ctrl+T for a new tab)."
echo "  2. Visit chrome://extensions"
echo "  3. Use 'Load unpacked' to add the plugin folders from /opt/SimplePOSPrint/plugins/text-mode and /opt/SimplePOSPrint/plugins/image-mode"
echo "     (Click 'Developer mode' at the top right to reveal 'Load unpacked'.)"
echo "  4. Select the correct folder, and it will load the extension."
echo
echo "Your AnyDesk address for remote support is:"
echo "  - Run: anydesk"
echo "  - Share the 9-digit code that appears."
echo
echo "Reboot now for everything to take effect:"
echo "  sudo reboot"
