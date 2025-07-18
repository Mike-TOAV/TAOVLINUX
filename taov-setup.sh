#!/bin/bash
set -e

echo "===== TAOV Till Post-Install Setup ====="

# 1. AnyDesk (repo, install)
echo "Installing AnyDesk..."
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk

# 2. Google Chrome (install .deb)
echo "Installing Google Chrome..."
wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get -y install /tmp/chrome.deb || apt-get -fy install

# 3. SimplePOSPrint (fetch & install as systemd service)
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

# 4. Imagemode Chrome extension from plugins dir
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
EXT_DST="/opt/chrome-extensions/imagemode"
mkdir -p "$EXT_DST"
cp -r "$PLUGIN_SRC"/* "$EXT_DST"

# 5. User & Openbox autologin, kiosk, wallpaper, menu
USERNAME="till"
HOMEDIR="/home/$USERNAME"
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi

sed -i 's/^#autologin-user=.*/autologin-user=till/' /etc/lightdm/lightdm.conf
sed -i '/^\[Seat:\*\]/a autologin-user=till' /etc/lightdm/lightdm.conf
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

mkdir -p "$HOMEDIR/.config/openbox"
cat > "$HOMEDIR/.config/openbox/autostart" <<EOFA
#!/bin/bash
matchbox-keyboard &
google-chrome --load-extension=/opt/chrome-extensions/imagemode --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
EOFA
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config"

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
chown $USERNAME:$USERNAME "$MENU_XML"

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
chown $USERNAME:$USERNAME "$OPENBOX_RC"

mkdir -p "$HOMEDIR/Pictures"
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/TAOV-Wallpaper.jpg
cat > "$HOMEDIR/.fehbg" <<EOFB
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOFB
echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.fehbg" "$HOMEDIR/.config/openbox/autostart"

echo "===== TAOV Till Post-Install Setup Complete ====="
