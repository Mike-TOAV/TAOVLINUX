#!/bin/bash
set -e
exec > >(tee /root/taov-setup.log) 2>&1
set -x

echo "===== TAOV Till Post-Install Setup ====="

# --- 1. Debloat: Remove unwanted packages
sed -i '/cdrom:/d' /etc/apt/sources.list
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter* google-chrome  || true
apt-get autoremove -y || true

# --- 2. Core: LightDM, CUPS, network/printer, AnyDesk, Chrome
apt-get update
apt-get install -y lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox matchbox-keyboard \
    python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator fonts-dejavu fonts-liberation mesa-utils feh

systemctl enable cups
systemctl start cups
usermod -aG lpadmin till

set +e
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk
set -e

wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get -y install /tmp/chrome.deb || apt-get -fy install

# --- 3. SimplePOSPrint (Python venv, service, plugin)
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

# --- 4. Imagemode Chrome extension
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
set -e

# --- 5. User till, LightDM, Openbox, rc.xml/menu, wallpaper
USERNAME="till"
HOMEDIR="/home/$USERNAME"

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi

# --- LightDM config for autologin and Openbox session
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

# --- Openbox: menu, autostart (with debug), wallpaper
mkdir -p "$HOMEDIR/.config/openbox"
mkdir -p "$HOMEDIR/Pictures"

# Autostart script with debug info
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

# Menu XML
cat > "$HOMEDIR/.config/openbox/menu.xml" <<EOMENU
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
EOMENU

# rc.xml: Add Ctrl+Alt+Space hotkey for menu
OPENBOX_RC="$HOMEDIR/.config/openbox/rc.xml"
if [ ! -f "$OPENBOX_RC" ]; then
  cp /etc/xdg/openbox/rc.xml "$OPENBOX_RC"
fi
awk '/<\/keyboard>/{
  print "    <keybind key=\"C-A-space\">"
  print "      <action name=\"ShowMenu\">"
  print "        <menu>root-menu</menu>"
  print "      </action>"
  print "    </keybind>"
}1' "$OPENBOX_RC" > "$OPENBOX_RC.new" && mv "$OPENBOX_RC.new" "$OPENBOX_RC"

# Wallpaper (download and set)
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/TAOV-Wallpaper.jpg
cat > "$HOMEDIR/.fehbg" <<EOFB
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOFB
echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"

# .xsession (must be executable and owned by till)
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown $USERNAME:$USERNAME "$HOMEDIR/.xsession"

# Ownership and permissions fix
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config/openbox"
chmod -R u+rwX,go+rX "$HOMEDIR/.config/openbox"
chown $USERNAME:$USERNAME "$HOMEDIR/.fehbg"
chmod 644 "$HOMEDIR/.fehbg"
chown -R $USERNAME:$USERNAME "$HOMEDIR/Pictures"

sudo -u $USERNAME openbox --reconfigure || true

# --- 6. GRUB splash and wallpaper from TAOVLINUX repo (safe, non-blocking)
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

# Set GRUB background image if present
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

# --- 10. Self-cleanup
rm -- "$0"
