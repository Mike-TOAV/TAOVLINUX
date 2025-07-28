#!/bin/bash
set -euo pipefail
exec > >(tee /root/taov-setup.log | tee /dev/tty) 2>&1
set -x

USERNAME="till"
HOMEDIR="/home/$USERNAME"
SPP_USER="spp"
SIMPLEPOS_DIR="/opt/spp"
EXT_DST="/opt/chrome-extensions/imagemode"
REPO_DIR="/opt/TAOVLINUX"
POPPINS_DIR="/usr/local/share/fonts/truetype/poppins"

safe_exec() { "$@" || echo "Warning: command failed: $*"; }

# 1. User setup
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi

# 2. Font config
cat > /etc/fonts/local.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Poppins</string></edit>
  </match>
</fontconfig>
EOF
fc-cache -f -v

# 3. Clean unwanted packages
sed -i '/cdrom:/d' /etc/apt/sources.list
safe_exec apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter
safe_exec apt-get autoremove -y
safe_exec apt-get purge -y google-chrome-stable chromium-browser snapd
rm -rf "$HOMEDIR/.config/google-chrome" "$HOMEDIR/.config/chromium" "$HOMEDIR/snap" /snap

# 4. Install essentials
apt-get update
apt-get install -y \
  lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox \
  python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator \
  mesa-utils feh konsole plank onboard chromium xcursor-themes adwaita-icon-theme-full passwd 

systemctl enable cups
systemctl start cups
usermod -aG lpadmin "$USERNAME"

# 5. AnyDesk
safe_exec wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
safe_exec apt-get -y install anydesk

# 6. SimplePOSPrint
if ! id "$SPP_USER" >/dev/null 2>&1; then
  useradd -r -m -s /bin/bash "$SPP_USER"
fi
if [ ! -d "$SIMPLEPOS_DIR" ]; then
  git clone https://github.com/Mike-TOAV/SimplePOSPrint.git "$SIMPLEPOS_DIR"
else
  cd "$SIMPLEPOS_DIR" && git pull
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
WorkingDirectory=$SIMPLEPOS_DIR
User=$SPP_USER
Group=$SPP_USER
ExecStart=$SIMPLEPOS_DIR/venv/bin/python3 $SIMPLEPOS_DIR/spp.py
Restart=on-failure
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
systemctl enable simpleposprint.service
systemctl restart simpleposprint.service

# 7. Chrome extension
mkdir -p "$EXT_DST"
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
[ -d "$PLUGIN_SRC" ] && cp -r "$PLUGIN_SRC"/* "$EXT_DST"
chown -R $USERNAME:$USERNAME "$EXT_DST"

# 8. LightDM config
if [ -f /etc/lightdm/lightdm.conf ]; then
  sed -i 's/^#autologin-user=.*/autologin-user=till/' /etc/lightdm/lightdm.conf
  sed -i '/^\[Seat:\*\]/a autologin-user=till\nuser-session=openbox' /etc/lightdm/lightdm.conf || true
fi
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

# 9. Install Poppins fonts
mkdir -p "$POPPINS_DIR"
POPPINS_FONTS=(
  Poppins-Regular.ttf Poppins-Bold.ttf Poppins-Italic.ttf
  Poppins-BoldItalic.ttf Poppins-Light.ttf Poppins-SemiBold.ttf
  Poppins-ExtraBold.ttf Poppins-Thin.ttf
)
for FONT in "${POPPINS_FONTS[@]}"; do
  wget -q -O "$POPPINS_DIR/$FONT" "https://github.com/google/fonts/raw/main/ofl/poppins/$FONT"
done
fc-cache -fv "$POPPINS_DIR"
chmod 644 "$POPPINS_DIR"/*.ttf

# 10. Arc-Dark theme
TMP_ARC=/tmp/arc-theme
mkdir -p "$TMP_ARC"
wget -O /tmp/arc-theme.tar.gz https://github.com/jnsh/arc-theme/archive/master.tar.gz
safe_exec tar -xzf /tmp/arc-theme.tar.gz -C "$TMP_ARC" --strip-components=1
safe_exec cp -r "$TMP_ARC/common/Arc-Dark" /usr/share/themes/Arc-Dark

# 11. Wallpaper
mkdir -p "$HOMEDIR/Pictures"
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/wallpapers/TAOV-Wallpaper.jpg
cat > "$HOMEDIR/.fehbg" <<EOF
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOF
chmod 644 "$HOMEDIR/.fehbg"

# 12. Cursor
mkdir -p "$HOMEDIR/.icons/default"
cat > "$HOMEDIR/.icons/default/index.theme" <<EOCURSOR
[Icon Theme]
Name=Adwaita
Inherits=Adwaita
EOCURSOR

echo "Xcursor.size: 24" >> "$HOMEDIR/.Xresources"
echo 'export XCURSOR_SIZE=24' >> "$HOMEDIR/.profile"

# 13. Onboard Keyboard Settings (Dark, Docked, Autohide)
mkdir -p "$HOMEDIR/.config/onboard"
cat > "$HOMEDIR/.config/onboard/onboard.conf" <<EOF
[Window]
docking=2
dock_iconified=false
xid_mode=normal

[Onboard]
theme=Blackboard
auto_hide=true
auto_show=true
auto_show_only_if_no_hardware_keyboard=true
EOF
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config/onboard"

# 14. Openbox menu and config
mkdir -p "$HOMEDIR/.config/openbox"
cat > "$HOMEDIR/.config/openbox/menu.xml" <<EOMENU
<openbox_menu>
  <menu id="root-menu" label="TAOV Menu">
    <item label="New Lightspeed Tab">
      <action name="Execute">
        <command>chromium https://aceofvapez.retail.lightspeed.app/ --load-extension=$EXT_DST --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble</command>
      </action>
    </item>
    <item label="SimplePOSPrint Config">
      <action name="Execute">
        <command>chromium http://localhost:5000/config.html\ --load-extension=$EXT_DST --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble</command>
      </action>
    </item>
    <item label="Open Admin Menu (Ctrl+Alt+A)">
      <action name="ShowMenu">
        <menu>admin-menu</menu>
      </action>
    </item>
  </menu>
  <menu id="admin-menu" label="TAOV Admin">
    <item label="Non-Kiosk Chromium">
      <action name="Execute">
        <command>chromium --no-sandbox --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble</command>
      </action>
    </item>
    <item label="Konsole Terminal">
      <action name="Execute">
        <command>konsole</command>
      </action>
    </item>
    <item label="Restart Openbox">
      <action name="Restart"/>
    </item>
    <item label="Shutdown">
      <action name="Execute"><command>systemctl poweroff</command></action>
    </item>
    <item label="Reboot">
      <action name="Execute"><command>systemctl reboot</command></action>
    </item>
    <item label="Logout">
      <action name="Exit"/>
    </item>
  </menu>
</openbox_menu>
EOMENU

RC_XML="$HOMEDIR/.config/openbox/rc.xml"
cp /etc/xdg/openbox/rc.xml "$RC_XML"
sed -i 's|<name>.*</name>|<name>Arc-Dark</name>|g' "$RC_XML"
sed -i 's|<font place=\"ActiveWindow\">.*</font>|<font place=\"ActiveWindow\">Poppins Bold 22</font>|g' "$RC_XML"
sed -i 's|<font place=\"InactiveWindow\">.*</font>|<font place=\"InactiveWindow\">Poppins 18</font>|g' "$RC_XML"

awk '
/<\/keyboard>/ {
  print "    <keybind key=\"C-A-space\">"
  print "      <action name=\"ShowMenu\"><menu>root-menu</menu></action>"
  print "    </keybind>"
  print "    <keybind key=\"C-A-a\">"
  print "      <action name=\"ShowMenu\"><menu>admin-menu</menu></action>"
  print "    </keybind>"
  print "    <keybind key=\"C-A-t\">"
  print "      <action name=\"Execute\"><command>konsole</command></action>"
  print "    </keybind>"
  print $0
  next
}
{ print }
' "$RC_XML" > "$RC_XML.new"
mv "$RC_XML.new" "$RC_XML"

chown -R $USERNAME:$USERNAME "$HOMEDIR/.config/openbox"

cat > "$HOMEDIR/.config/openbox/autostart" <<EOFA
#!/bin/bash
xsetroot -cursor_name left_ptr
export XCURSOR_SIZE=48
onboard &
plank &
[ -f "\$HOME/.fehbg" ] && bash "\$HOME/.fehbg" &
pkill chromium || true
chromium --app="https://aceofvapez.retail.lightspeed.app/" --load-extension=$EXT_DST --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble &
EOFA
chmod +x "$HOMEDIR/.config/openbox/autostart"

# 15. Wallpaper, Xsession, chown
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown -R $USERNAME:$USERNAME "$HOMEDIR"
rm -f "$HOMEDIR/.Xauthority"

# 16. GRUB splash
if [ ! -d "$REPO_DIR" ]; then
  git clone https://github.com/Mike-TOAV/TAOVLINUX.git "$REPO_DIR"
else
  cd "$REPO_DIR" && git pull
fi
GRUB_BG_SRC="$REPO_DIR/wallpapers/taov-grub.png"
GRUB_BG_DST="/boot/grub/taov-grub.png"
if [ -f "$GRUB_BG_SRC" ]; then
  cp "$GRUB_BG_SRC" "$GRUB_BG_DST"
  chmod 644 "$GRUB_BG_DST"
  if ! grep -q "GRUB_BACKGROUND=" /etc/default/grub; then
    echo "GRUB_BACKGROUND=\"$GRUB_BG_DST\"" >> /etc/default/grub
  else
    sed -i "s|^GRUB_BACKGROUND=.*|GRUB_BACKGROUND=\"$GRUB_BG_DST\"|" /etc/default/grub
  fi
  update-grub
fi

# 17. Plank configuration (launchers)
configure_plank() {
  mkdir -p "$HOMEDIR/.config/plank/dock1/launchers"
  rm -f "$HOMEDIR/.config/plank/dock1/launchers"/*.dockitem

  cat > "$HOMEDIR/.config/plank/dock1/launchers/chromium-pos.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=chromium --app=https://aceofvapez.retail.lightspeed.app/ --load-extension=$EXT_DST --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble
EOF

  cat > "$HOMEDIR/.config/plank/dock1/launchers/simpleposprint-config.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=chromium --app=http://localhost:5000/config.html --load-extension=$EXT_DST --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble
EOF

  cat > "$HOMEDIR/.config/plank/dock1/launchers/shutdown.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=systemctl poweroff
EOF

  cat > "$HOMEDIR/.config/plank/dock1/launchers/reboot.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=systemctl reboot
EOF

  cat > "$HOMEDIR/.config/plank/dock1/launchers/update.dockitem" <<EOF
[PlankDockItemPreferences]
Launcher=konsole -e sudo apt update && sudo apt upgrade
EOF

  chown -R $USERNAME:$USERNAME "$HOMEDIR/.config/plank"
}
configure_plank

# 18. Network failover watchdog
generate_network_failover_script() {
  cat > /usr/local/bin/taov-netcheck.sh <<'EOF'
#!/bin/bash
while true; do
  if ! ping -q -c 1 -W 5 8.8.8.8 >/dev/null; then
    logger -t taov-netcheck "No internet detected — launching network manager UI."
    pkill nm-connection-editor || true
    sudo -u till DISPLAY=:0 XAUTHORITY=/home/till/.Xauthority nm-connection-editor &
    sleep 300
  else
    sleep 300
  fi
done
EOF
  chmod +x /usr/local/bin/taov-netcheck.sh

  cat > /etc/systemd/system/taov-netcheck.service <<EOF2
[Unit]
Description=TAOV Network Failover Checker
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/taov-netcheck.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF2

  systemctl daemon-reload
  systemctl enable taov-netcheck.service
  systemctl start taov-netcheck.service
}
generate_network_failover_script

# 19. Final Openbox reload and log
sudo -u $USERNAME openbox --reconfigure || true
echo "===== Setup Complete ====="
