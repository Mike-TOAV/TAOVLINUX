#!/bin/bash
set -euo pipefail
exec > >(tee /root/taov-setup.log) 2>&1
set -x

echo "===== TAOV Till Post-Install Setup ====="

USERNAME="till"
HOMEDIR="/home/$USERNAME"

# --- 1. User creation and home dir permissions (before anything else)
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi
mkdir -p "$HOMEDIR"
chown "$USERNAME:$USERNAME" "$HOMEDIR"

# --- 2. Debloat & Remove Chrome, Snap
sed -i '/cdrom:/d' /etc/apt/sources.list
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter  || true
apt-get autoremove -y || true

set +e
apt-get purge -y google-chrome-stable chromium chromium-browser snapd
rm -rf "$HOMEDIR/.config/google-chrome" "$HOMEDIR/snap" /snap
set -e

# --- 3. Core system install (always as root)
apt-get update
apt-get install -y lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox matchbox-keyboard \
    python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator fonts-dejavu fonts-liberation mesa-utils feh

systemctl enable cups
systemctl start cups

# --- 4. Printing permissions
usermod -aG lpadmin $USERNAME

# --- 5. AnyDesk (robust)
set +e
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk
set -e

# --- 6. SimplePOSPrint (Python venv, service, plugin)
SIMPLEPOS_DIR="/opt/spp"
SPP_USER="spp"
if ! id "$SPP_USER" >/dev/null 2>&1; then
  useradd -r -m -s /bin/bash "$SPP_USER"
fi
if [ ! -d "$SIMPLEPOS_DIR" ]; then
  git clone https://github.com/Mike-TOAV/SimplePOSPrint.git "$SIMPLEPOS_DIR"
else
  cd "$SIMPLEPOS_DIR"
  git pull
fi
cd "$SIMPLEPOS_DIR"
python3 -m venv venv
. venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
chown -R $SPP_USER:$SPP_USER "$SIMPLEPOS_DIR"
cat > /etc/systemd/system/simpleposprint.service <<EOF2
[Unit]
Description=SimplePOSPrint Flask Bridge
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/spp
User=spp
Group=spp
ExecStart=/opt/spp/venv/bin/python3 /opt/spp/spp.py
Restart=on-failure
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF2
systemctl daemon-reload
systemctl enable simpleposprint.service
systemctl restart simpleposprint.service

# --- 7. Create user config dirs and set ownership IMMEDIATELY
mkdir -p "$HOMEDIR/.config/openbox"
mkdir -p "$HOMEDIR/Pictures"
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config"
chown -R $USERNAME:$USERNAME "$HOMEDIR/Pictures"
chmod -R u+rwX,go+rX "$HOMEDIR/.config"
chmod -R u+rwX,go+rX "$HOMEDIR/Pictures"

# --- 8. LightDM config for autologin and Openbox session
if [ -f /etc/lightdm/lightdm.conf ]; then
  sed -i 's/^#autologin-user=.*/autologin-user=till/' /etc/lightdm/lightdm.conf
  sed -i '/^\[Seat:\*\]/a autologin-user=till' /etc/lightdm/lightdm.conf
  if ! grep -q "user-session=openbox" /etc/lightdm/lightdm.conf; then
    sed -i '/^\[Seat:\*\]/a user-session=openbox' /etc/lightdm/lightdm.conf
  fi
else
  echo "WARNING: /etc/lightdm/lightdm.conf not found! Skipping autologin setup."
fi
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

echo -e "[Desktop]\nSession=openbox" > "$HOMEDIR/.dmrc"
chown $USERNAME:$USERNAME "$HOMEDIR/.dmrc"

# --- 9. Openbox: menu, autostart, rc.xml, wallpaper (create+chown in sequence)
cat > "$HOMEDIR/.config/openbox/autostart" <<'EOFA'
#!/bin/bash
echo "AUTOSTART USER: $(whoami)" > /tmp/taov-autostart.log
echo "AUTOSTART HOME: $HOME" >> /tmp/taov-autostart.log
ls -l ~/.config/openbox/autostart >> /tmp/taov-autostart.log
ls -l ~/.xsession >> /tmp/taov-autostart.log
matchbox-keyboard &
google-chrome --load-extension=/opt/chrome-extensions/imagemode --kiosk --no-sandbox --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
echo "AUTOSTART: done $(date)" >> /tmp/taov-autostart.log
EOFA
chmod +x "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

OPENBOX_RC="$HOMEDIR/.config/openbox/rc.xml"
if [ ! -f "$OPENBOX_RC" ]; then
  cp /etc/xdg/openbox/rc.xml "$OPENBOX_RC"
  chown $USERNAME:$USERNAME "$OPENBOX_RC"
fi
awk '/<\/keyboard>/{
  print "    <keybind key=\"C-A-space\">"
  print "      <action name=\"ShowMenu\">"
  print "        <menu>root-menu</menu>"
  print "      </action>"
  print "    </keybind>"
}1' "$OPENBOX_RC" > "$OPENBOX_RC.new" && mv "$OPENBOX_RC.new" "$OPENBOX_RC"
chown $USERNAME:$USERNAME "$OPENBOX_RC"

cat > "$HOMEDIR/.config/openbox/menu.xml" <<'EOMENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
<menu id="root-menu" label="TAOV Menu">
  <item label="New Lightspeed Tab">
    <action name="Execute">
      <command>google-chrome --load-extension=/opt/chrome-extensions/imagemode --new-window "https://aceofvapez.retail.lightspeed.app/"</command>
    </action>
  </item>
  <item label="Non-Kiosk Chrome">
    <action name="Execute">
      <command>google-chrome --load-extension=/opt/chrome-extensions/imagemode --no-sandbox --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble</command>
    </action>
  </item>
  <item label="SimplePOSPrint Config">
    <action name="Execute">
      <command>google-chrome --load-extension=/opt/chrome-extensions/imagemode --no-sandbox --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "http://localhost:5000/config.html"</command>
    </action>
  </item>
</menu>
</openbox_menu>
EOMENU
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/menu.xml"

# Wallpaper download and chown
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/TAOV-Wallpaper.jpg
chown $USERNAME:$USERNAME "$HOMEDIR/Pictures/taov-wallpaper.jpg"
cat > "$HOMEDIR/.fehbg" <<EOF
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOF
chown $USERNAME:$USERNAME "$HOMEDIR/.fehbg"
chmod 644 "$HOMEDIR/.fehbg"
echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

# .xsession setup (create+chown+chmod last)
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown $USERNAME:$USERNAME "$HOMEDIR/.xsession"

# Force till ownership on ALL home subdirs (belt and braces!)
chown -R $USERNAME:$USERNAME "$HOMEDIR"

# Remove possible stale Xauthority (prevents X session bugs)
rm -f "$HOMEDIR/.Xauthority"
chown $USERNAME:$USERNAME "$HOMEDIR"

sudo -u $USERNAME openbox --reconfigure || true

# --- 10. Chrome install (ensure no snap, use .deb, retry logic, at very end)
CHROME_DEB="/root/chrome.deb"
wget -O "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

for i in 1 2; do
  if dpkg-deb -I "$CHROME_DEB" >/dev/null 2>&1; then
    break
  else
    echo "WARN: Chrome .deb corrupted or incomplete, retrying ($i)..."
    rm -f "$CHROME_DEB"
    sleep 1
    wget -O "$CHROME_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  fi
done

if ! dpkg-deb -I "$CHROME_DEB" >/dev/null 2>&1; then
  echo "ERROR: Chrome .deb is still corrupt after retries! Exiting setup."
  exit 1
fi

dpkg -i "$CHROME_DEB" || apt-get -fy install

# --- 11. Imagemode Chrome extension (repeat in case plugin path was not there at Chrome install time)
set +e
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
EXT_DST="/opt/chrome-extensions/imagemode"
echo "Copying Imagemode Chrome extension from $PLUGIN_SRC to $EXT_DST..."
mkdir -p "$EXT_DST"
if [ -d "$PLUGIN_SRC" ]; then
  cp -r "$PLUGIN_SRC"/* "$EXT_DST"
  echo "Imagemode extension copied."
else
  echo "WARNING: Imagemode plugin directory not found: $PLUGIN_SRC"
fi
chown -R $USERNAME:$USERNAME "$EXT_DST"
set -e

# --- 12. GRUB splash from TAOVLINUX repo (non-blocking)
set +e
REPO_URL="https://github.com/Mike-TOAV/TAOVLINUX.git"
REPO_DIR="/opt/TAOVLINUX"
if [ ! -d "$REPO_DIR" ]; then
  echo "Cloning TAOVLINUX repo to $REPO_DIR..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "Updating TAOVLINUX repo in $REPO_DIR..."
  cd "$REPO_DIR"
  git pull
  cd -
fi

GRUB_BG_SRC="$REPO_DIR/wallpapers/taov-grub.png"
GRUB_BG_DST="/boot/grub/taov-grub.png"
if [ -f "$GRUB_BG_SRC" ]; then
  cp "$GRUB_BG_SRC" "$GRUB_BG_DST"
  chmod 644 "$GRUB_BG_DST"
  if ! grep -q "GRUB_BACKGROUND=" /etc/default/grub; then
    echo "GRUB_BACKGROUND=\"$GRUB_BG_DST\"" | tee -a /etc/default/grub
  else
    sed -i "s|^GRUB_BACKGROUND=.*|GRUB_BACKGROUND=\"$GRUB_BG_DST\"|" /etc/default/grub
  fi
  update-grub
  echo "GRUB background image set!"
else
  echo "GRUB background image not found!"
fi
set -e

echo "===== TAOV Till Post-Install Setup Complete ====="

# --- 13. Self-cleanup
rm -- "$0"
