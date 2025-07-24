#!/bin/bash
set -euo pipefail
exec > >(tee /root/taov-setup.log) 2>&1
set -x

echo "===== TAOV Till Post-Install Setup ====="

USERNAME="till"
HOMEDIR="/home/$USERNAME"

# --- 1. User creation (first!)
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi
mkdir -p "$HOMEDIR"
chown "$USERNAME:$USERNAME" "$HOMEDIR"

# --- 2. Debloat (remove cruft)
sed -i '/cdrom:/d' /etc/apt/sources.list
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter || true
apt-get autoremove -y || true
set +e
apt-get purge -y google-chrome-stable chromium chromium-browser snapd
rm -rf "$HOMEDIR/.config/google-chrome" "$HOMEDIR/snap" /snap
set -e

# --- 3. Core packages and services
apt-get update
apt-get install -y lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox matchbox-keyboard \
    python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator fonts-dejavu fonts-liberation mesa-utils feh konsole

systemctl enable cups
systemctl start cups
usermod -aG lpadmin "$USERNAME"

# --- 4. AnyDesk (ignore failures)
set +e
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk
set -e

# --- 5. SimplePOSPrint (systemd, venv, plugins)
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

# --- 6. Imagemode Chrome extension (copy for policy load, not via --load-extension)
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
EXT_DST="/opt/chrome-extensions/imagemode"
mkdir -p "$EXT_DST"
if [ -d "$PLUGIN_SRC" ]; then
  cp -r "$PLUGIN_SRC"/* "$EXT_DST"
else
  echo "WARNING: Imagemode plugin directory not found: $PLUGIN_SRC"
fi
chown -R $USERNAME:$USERNAME "$EXT_DST"

# --- 8. User config directories and permissions
mkdir -p "$HOMEDIR/.config/openbox"
mkdir -p "$HOMEDIR/Pictures"
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config"
chown -R $USERNAME:$USERNAME "$HOMEDIR/Pictures"
chmod -R u+rwX,go+rX "$HOMEDIR/.config"
chmod -R u+rwX,go+rX "$HOMEDIR/Pictures"

# --- 9. LightDM config (autologin and openbox session)
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

# --- 10. Openbox: menu, autostart, rc.xml, wallpaper
cat > "$HOMEDIR/.config/openbox/autostart" <<'EOFA'
#!/bin/bash
matchbox-keyboard &
google-chrome --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
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
  print "    <keybind key=\"C-A-a\">"
  print "      <action name=\"ShowMenu\">"
  print "       <menu>admin-menu</menu>"
  print "       </action>"
  print "     </keybind>"
  print "    <keybind key=\"C-A-t\">"
  print "       <action name=\"Execute\">"
  print "          <command>konsole</command>"
  print "          <startupnotify><enabled>yes</enabled></startupnotify>"
  print "        </action>"
  print "     </keybind>"
}1' "$OPENBOX_RC" > "$OPENBOX_RC.new" && mv "$OPENBOX_RC.new" "$OPENBOX_RC"
chown $USERNAME:$USERNAME "$OPENBOX_RC"

cat > "$HOMEDIR/.config/openbox/menu.xml" <<'EOMENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <!-- TAOV Menu -->
  <menu id="root-menu" label="TAOV Menu">
    <item label="New Lightspeed Tab">
      <action name="Execute">
        <command>google-chrome --new-window "https://aceofvapez.retail.lightspeed.app/"</command>
      </action>
    </item>
    <item label="Non-Kiosk Chrome">
      <action name="Execute">
        <command>google-chrome --no-sandbox --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble</command>
      </action>
    </item>
    <item label="SimplePOSPrint Config">
      <action name="Execute">
        <command>google-chrome --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "http://localhost:5000/config.html"</command>
      </action>
    </item>
  </menu>
  <!-- Admin menu -->
  <menu id="admin-menu" label="Admin Menu">
   <menu id="applications-menu" label="Applications" execute="/usr/bin/obamenu"/>
    <item label="Konsole">
      <action name="Execute">
        <command>konsole</command>
        <startupnotify><enabled>yes</enabled></startupnotify>
      </action>
    </item>
    <separator />
    <item label="Restart Openbox">
      <action name="Restart" />
    </item>
  </menu>
</openbox_menu>
EOMENU
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/menu.xml"

wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/TAOV-Wallpaper.jpg
chown $USERNAME:$USERNAME "$HOMEDIR/Pictures/taov-wallpaper.jpg"
cat > "$HOMEDIR/.fehbg" <<EOF
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOF
chown $USERNAME:$USERNAME "$HOMEDIR/.fehbg"
chmod 644 "$HOMEDIR/.fehbg"
echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown $USERNAME:$USERNAME "$HOMEDIR/.xsession"

chown -R $USERNAME:$USERNAME "$HOMEDIR"

rm -f "$HOMEDIR/.Xauthority"
chown $USERNAME:$USERNAME "$HOMEDIR"

sudo -u $USERNAME openbox --reconfigure || true

# --- 12. Chrome install (.deb, retry logic, at very end)
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

# --- 7. Chrome Enterprise Policy to force-load unpacked extension
POLICY_DIR="/etc/opt/chrome/policies/managed"
POLICY_FILE="$POLICY_DIR/taov-imagemode-policy.json"
mkdir -p "$POLICY_DIR"
cat > "$POLICY_FILE" <<EOF
{
  "ExtensionSettings": {
    "*": {
      "installation_mode": "allowed"
    },
    "file:///opt/chrome-extensions/imagemode": {
      "installation_mode": "force_installed"
    }
  }
}
EOF
chmod 644 "$POLICY_FILE"

# --- 13. GRUB splash (non-blocking, after all else)
set +e
REPO_URL="https://github.com/Mike-TOAV/TAOVLINUX.git"
REPO_DIR="/opt/TAOVLINUX"
if [ ! -d "$REPO_DIR" ]; then
  git clone "$REPO_URL" "$REPO_DIR"
else
  cd "$REPO_DIR" && git pull
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

rm -- "$0"
