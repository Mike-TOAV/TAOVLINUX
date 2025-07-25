#!/bin/bash
set -euo pipefail
exec > >(tee /root/taov-setup.log) 2>&1
set -x

echo "===== TAOV Till Post-Install Setup (Touch Friendly, Modern) ====="

USERNAME="till"
HOMEDIR="/home/$USERNAME"

# 1. User setup and font preference
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi
mkdir -p "$HOMEDIR"
chown "$USERNAME:$USERNAME" "$HOMEDIR"

# Set Poppins as default sans font systemwide
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

# 2. Remove unnecessary packages (fast/clean install)
sed -i '/cdrom:/d' /etc/apt/sources.list
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter || true
apt-get autoremove -y || true
set +e
apt-get purge -y google-chrome-stable chromium-browser snapd
rm -rf "$HOMEDIR/.config/google-chrome" "$HOMEDIR/.config/chromium" "$HOMEDIR/snap" /snap
set -e

# 3. Core system: Chromium, touch, big cursor, feh, openbox, etc.
apt-get update
apt-get install -y \
  lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox \
  python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator \
  mesa-utils feh konsole onboard chromium plank adwaita-icon-theme-full xcursor-themes

systemctl enable cups
systemctl start cups
usermod -aG lpadmin "$USERNAME"

# 4. AnyDesk (robust, ignore failure)
set +e
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk
set -e

# 5. SimplePOSPrint (systemd, venv, plugins)
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

# 6. Imagemode extension for Chromium
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
EXT_DST="/opt/chrome-extensions/imagemode"
mkdir -p "$EXT_DST"
if [ -d "$PLUGIN_SRC" ]; then
  cp -r "$PLUGIN_SRC"/* "$EXT_DST"
fi
chown -R $USERNAME:$USERNAME "$EXT_DST"

# 7. Poppins font (direct GitHub fetch)
POPPINS_DIR="/usr/local/share/fonts/truetype/poppins"
mkdir -p "$POPPINS_DIR"
POPPINS_FONTS=(
  "Poppins-Regular.ttf"
  "Poppins-Bold.ttf"
  "Poppins-Italic.ttf"
  "Poppins-BoldItalic.ttf"
  "Poppins-Light.ttf"
  "Poppins-SemiBold.ttf"
  "Poppins-ExtraBold.ttf"
  "Poppins-Thin.ttf"
)
for FONT in "${POPPINS_FONTS[@]}"; do
  wget -q -O "$POPPINS_DIR/$FONT" "https://github.com/google/fonts/raw/main/ofl/poppins/$FONT"
done
fc-cache -fv "$POPPINS_DIR"
chown -R root:root "$POPPINS_DIR"
chmod 644 "$POPPINS_DIR"/*.ttf

# 8. Arc-Dark GTK/Openbox theme (modern, high contrast)
ARC_DARK_DIR="/usr/share/themes/Arc-Dark"
wget -O /tmp/arc-theme.tar.gz https://github.com/jnsh/arc-theme/archive/master.tar.gz
rm -rf /usr/share/themes/Arc /usr/share/themes/Arc-Dark
mkdir -p /usr/share/themes/Arc
tar -xzf /tmp/arc-theme.tar.gz --strip-components=1 -C /usr/share/themes/Arc
if [ -d "/usr/share/themes/Arc/Arc-Dark" ]; then
  cp -r /usr/share/themes/Arc/Arc-Dark "$ARC_DARK_DIR"
fi

# 9. User config dirs and permissions (fresh start)
mkdir -p "$HOMEDIR/.config/openbox"
mkdir -p "$HOMEDIR/Pictures"
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config"
chown -R $USERNAME:$USERNAME "$HOMEDIR/Pictures"
chmod -R u+rwX,go+rX "$HOMEDIR/.config"
chmod -R u+rwX,go+rX "$HOMEDIR/Pictures"

# 10. Openbox: Modern config (touch, theme, autostart, menus)
cat > "$HOMEDIR/.config/openbox/autostart" <<'EOFA'
#!/bin/bash
export XCURSOR_SIZE=48
xsetroot -cursor_name left_ptr
# Onboard on-screen keyboard (docked, blackboard theme, autohide)
onboard &
# Touch dock (Plank)
plank &
# Wallpaper (feh, use $HOME for user)
[ -f "$HOME/.fehbg" ] && bash "$HOME/.fehbg" &
# Kiosk with SimplePOSPrint extension
pkill chromium || true
chromium --load-extension=/opt/chrome-extensions/imagemode --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
EOFA
chmod +x "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

# Modern theme, big font, Arc-Dark, and keybinds in rc.xml
OPENBOX_RC="$HOMEDIR/.config/openbox/rc.xml"
if [ ! -f "$OPENBOX_RC" ]; then
  cp /etc/xdg/openbox/rc.xml "$OPENBOX_RC"
fi
sed -i '
  s|<font place="ActiveWindow">.*</font>|<font place="ActiveWindow">Poppins Bold 22</font>|g;
  s|<font place="InactiveWindow">.*</font>|<font place="InactiveWindow">Poppins 18</font>|g;
  s|<font place="MenuHeader">.*</font>|<font place="MenuHeader">Poppins Bold 22</font>|g;
  s|<font place="MenuItem">.*</font>|<font place="MenuItem">Poppins 20</font>|g;
  s|<font place="ActiveOnScreenDisplay">.*</font>|<font place="ActiveOnScreenDisplay">Poppins 26</font>|g;
  s|<font place="InactiveOnScreenDisplay">.*</font>|<font place="InactiveOnScreenDisplay">Poppins 22</font>|g;
  s|<name>.*</name>|<name>Arc-Dark</name>|g;
' "$OPENBOX_RC"
chown $USERNAME:$USERNAME "$OPENBOX_RC"

awk '/<\/keyboard>/{
  print "    <keybind key=\"C-A-space\">"
  print "      <action name=\"ShowMenu\">"
  print "        <menu>root-menu</menu>"
  print "      </action>"
  print "    </keybind>"
  print "    <keybind key=\"C-A-a\">"
  print "      <action name=\"ShowMenu\">"
  print "        <menu>admin-menu</menu>"
  print "      </action>"
  print "    </keybind>"
  print "    <keybind key=\"C-A-t\">"
  print "      <action name=\"Execute\">"
  print "        <command>konsole</command>"
  print "        <startupnotify><enabled>yes</enabled></startupnotify>"
  print "      </action>"
  print "    </keybind>"
}1' "$OPENBOX_RC" > "$OPENBOX_RC.new" && mv "$OPENBOX_RC.new" "$OPENBOX_RC"
chown $USERNAME:$USERNAME "$OPENBOX_RC"

# Openbox menu.xml (modern, TAOV/admin, touch friendly)
cat > "$HOMEDIR/.config/openbox/menu.xml" <<'EOMENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="TAOV Touch">
    <item label="New Lightspeed Tab">
      <action name="Execute">
        <command>chromium --new-window "https://aceofvapez.retail.lightspeed.app/"</command>
      </action>
    </item>
    <item label="SimplePOSPrint Config">
      <action name="Execute">
        <command>chromium --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "http://localhost:5000/config.html"</command>
      </action>
    </item>
    <separator/>
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
        <startupnotify><enabled>yes</enabled></startupnotify>
      </action>
    </item>
    <separator/>
    <item label="Restart Openbox">
      <action name="Restart" />
    </item>
  </menu>
</openbox_menu>
EOMENU
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/menu.xml"

# Wallpaper (TAOV branded)
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/TAOV-Wallpaper.jpg
chown $USERNAME:$USERNAME "$HOMEDIR/Pictures/taov-wallpaper.jpg"
cat > "$HOMEDIR/.fehbg" <<EOF
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOF
chown $USERNAME:$USERNAME "$HOMEDIR/.fehbg"
chmod 644 "$HOMEDIR/.fehbg"

echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

# .xsession for autologin
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown $USERNAME:$USERNAME "$HOMEDIR/.xsession"

chown -R $USERNAME:$USERNAME "$HOMEDIR"
rm -f "$HOMEDIR/.Xauthority"
chown $USERNAME:$USERNAME "$HOMEDIR"

# --- Touch-friendly cursor: Adwaita, 24px
echo "Xcursor.size: 24" >> "$HOMEDIR/.Xresources"
cat > /home/till/.icons/default/index.theme <<EOCURSOR
[Icon Theme]
Name=Adwaita
Inherits=Adwaita
EOCURSOR
chown -R till:till /home/till/.icons
echo 'export XCURSOR_SIZE=24' >> /home/till/.profile
echo 'export XCURSOR_SIZE=24' >> /home/till/.xsessionrc
echo 'export XCURSOR_THEME=Adwaita' >> /home/till/.profile
echo 'export XCURSOR_THEME=Adwaita' >> /home/till/.xsessionrc

# --- Onboard config: autohide if physical keyboard, blackboard theme, dock bottom
sudo -u till mkdir -p /home/till/.config/onboard
cat > /home/till/.config/onboard/onboard.conf <<EOF
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
chown -R till:till /home/till/.config/onboard

# --- Final: GRUB splash (TAOV)
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
fi
set -e

echo "===== TAOV Till Post-Install Setup Complete ====="
rm -- "$0"
