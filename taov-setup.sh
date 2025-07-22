#!/bin/bash
set -e
exec > >(tee /root/taov-setup.log) 2>&1
set -x

echo "===== TAOV Till Post-Install Setup ====="

# Remove cdrom repo if present (prevents apt-get errors)
sed -i '/cdrom:/d' /etc/apt/sources.list

# --- 1. DEBLOAT! Purge any unwanted packages just in case ---
echo "Purging unwanted packages..."
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter || true
apt-get autoremove -y || true

# --- 2. Ensure LightDM is installed and available ---
echo "Checking and (re)installing LightDM if needed..."
apt-get update
apt-get install -y lightdm

# --- 3. CUPS and printer tools ---
echo "Installing CUPS and printer setup tools..."
apt-get install -y cups system-config-printer
systemctl enable cups
systemctl start cups
usermod -aG lpadmin till

# --- 4. AnyDesk (repo, install) ---
set +e
echo "Installing AnyDesk..."
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk
set -e

# --- 5. Google Chrome (install .deb) ---
echo "Installing Google Chrome..."
wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get -y install /tmp/chrome.deb || apt-get -fy install

# --- 6. SimplePOSPrint (fetch & install as systemd service) ---
echo "Setting up SimplePOSPrint..."
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

# --- 7. Imagemode Chrome extension from plugins dir ---
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

# --- 8. User, LightDM autologin, Openbox config, menu, wallpaper ---
USERNAME="till"
HOMEDIR="/home/$USERNAME"

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi

# Safe LightDM config (autologin and display manager)
if [ -f /etc/lightdm/lightdm.conf ]; then
  sed -i 's/^#autologin-user=.*/autologin-user=till/' /etc/lightdm/lightdm.conf
  sed -i '/^\[Seat:\*\]/a autologin-user=till' /etc/lightdm/lightdm.conf
else
  echo "WARNING: /etc/lightdm/lightdm.conf not found! Skipping autologin setup."
fi
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

# Robust Openbox config/menu block
set +e

mkdir -p "$HOMEDIR/.config/openbox"

# Autostart script
cat > "$HOMEDIR/.config/openbox/autostart" <<EOFA
#!/bin/bash
matchbox-keyboard &
google-chrome --load-extension=/opt/chrome-extensions/imagemode --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
EOFA

# Custom menu.xml
MENU_XML="$HOMEDIR/.config/openbox/menu.xml"
cat > "$MENU_XML" <<EOMENU
<menu id="root-menu" label="TAOV Menu">
  <item label="New Lightspeed Tab">
    <action name="Execute">
      <command>google-chrome --load-extension=/opt/chrome-extensions/imagemode --new-window "https://aceofvapez.retail.lightspeed.app/"</command>
    </action>
  </item>
  <item label="Non-Kiosk Chrome">
    <action name="Execute">
      <command>google-chrome --load-extension=/opt/chrome-extensions/imagemode --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble</command>
    </action>
  </item>
  <item label="SimplePOSPrint Config">
    <action name="Execute">
      <command>google-chrome --load-extension=/opt/chrome-extensions/imagemode --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "http://localhost:5000/config.html"</command>
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

chown -R $USERNAME:$USERNAME "$HOMEDIR/.config/openbox"

sudo -u $USERNAME openbox --reconfigure || true

# --- Ensure TAOVLINUX repo is present and up to date ---
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

# --- Set GRUB background image ---
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

# --- Set desktop wallpaper ---
USERNAME="till"
HOMEDIR="/home/$USERNAME"
WALLPAPER_SRC="$REPO_DIR/wallpapers/TAOV-Wallpaper.jpg"
WALLPAPER_DST="$HOMEDIR/Pictures/taov-wallpaper.jpg"
if [ -f "$WALLPAPER_SRC" ]; then
  cp "$WALLPAPER_SRC" "$WALLPAPER_DST"
  chown "$USERNAME:$USERNAME" "$WALLPAPER_DST"
  echo "Wallpaper copied to $WALLPAPER_DST"
else
  echo "Desktop wallpaper not found!"
fi

# Set Openbox as default session for till user
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chown $USERNAME:$USERNAME "$HOMEDIR/.xsession"

set -e

echo "===== TAOV Till Post-Install Setup Complete ====="

# --- 10. Self-cleanup
rm -- "$0"
