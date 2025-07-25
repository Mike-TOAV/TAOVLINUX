#!/bin/bash
set -euo pipefail
exec > >(tee /root/taov-setup.log) 2>&1
set -x

echo "===== TAOV Till Post-Install Setup (Touch Friendly) ====="

USERNAME="till"
HOMEDIR="/home/$USERNAME"

# 1. User setup
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi
mkdir -p "$HOMEDIR"
chown "$USERNAME:$USERNAME" "$HOMEDIR"
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

# 2. Remove cruft and Chrome
sed -i '/cdrom:/d' /etc/apt/sources.list
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter || true
apt-get autoremove -y || true
set +e
apt-get purge -y google-chrome-stable chromium-browser snapd
rm -rf "$HOMEDIR/.config/google-chrome" "$HOMEDIR/.config/chromium" "$HOMEDIR/snap" /snap
set -e

# 3. Core packages: chromium, touch stuff, dock, keyboard, big fonts, etc.
apt-get update
apt-get install -y \
  lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox \
  python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator \
  mesa-utils feh konsole plank onboard chromium xcursor-themes

systemctl enable cups
systemctl start cups
usermod -aG lpadmin "$USERNAME"

# 4. AnyDesk (ignore failures)
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

# 6. Imagemode Chrome extension (for Chromium)
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
EXT_DST="/opt/chrome-extensions/imagemode"
mkdir -p "$EXT_DST"
if [ -d "$PLUGIN_SRC" ]; then
  cp -r "$PLUGIN_SRC"/* "$EXT_DST"
else
  echo "WARNING: Imagemode plugin directory not found: $PLUGIN_SRC"
fi
chown -R $USERNAME:$USERNAME "$EXT_DST"

# 7. User config directories and permissions
mkdir -p "$HOMEDIR/.config/openbox"
mkdir -p "$HOMEDIR/Pictures"
chown -R $USERNAME:$USERNAME "$HOMEDIR/.config"
chown -R $USERNAME:$USERNAME "$HOMEDIR/Pictures"
chmod -R u+rwX,go+rX "$HOMEDIR/.config"
chmod -R u+rwX,go+rX "$HOMEDIR/Pictures"

# 8. LightDM config (autologin and openbox session)
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

# --- TAOV: Install Poppins font family (touch-friendly, modern)
POPPINS_DIR="/usr/local/share/fonts/truetype/poppins"
POPPINS_ZIP="/tmp/Poppins.zip"
mkdir -p "$POPPINS_DIR"
wget -O "$POPPINS_ZIP" "https://fonts.google.com/download?family=Poppins"
unzip -o "$POPPINS_ZIP" -d "$POPPINS_DIR"
fc-cache -f
chown -R root:root "$POPPINS_DIR"
chmod 644 "$POPPINS_DIR"/*.ttf

# 9. Openbox: Modern theme, touch settings, menu, dock autostart, wallpaper
# ---- Download & install a TAOV Openbox theme (dark, modern, big touch targets)
THEME_DIR="/usr/share/themes/Obsidian-2"
if [ ! -d "$THEME_DIR" ]; then
  wget -O /tmp/obsidian-2.tar.gz https://github.com/jnsh/obsidian-2/archive/refs/heads/master.tar.gz
  tar -xf /tmp/obsidian-2.tar.gz -C /usr/share/themes
  mv /usr/share/themes/obsidian-2-master "$THEME_DIR"
fi

cat > "$HOMEDIR/.config/openbox/autostart" <<'EOFA'
#!/bin/bash
# Set large cursor
xsetroot -cursor_name left_ptr
export XCURSOR_SIZE=48
# Onscreen keyboard
onboard &
# Touch dock (Plank)
plank &
# Set wallpaper (if not already set)
[ -f "$HOME/.fehbg" ] && bash "$HOME/.fehbg" &
# Chromium with plugin
pkill chromium || true
chromium --load-extension=/opt/chrome-extensions/imagemode --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
EOFA
chmod +x "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

# --- Set up touch-friendly Openbox theme and big font (rc.xml)
OPENBOX_RC="$HOMEDIR/.config/openbox/rc.xml"
if [ ! -f "$OPENBOX_RC" ]; then
  cp /etc/xdg/openbox/rc.xml "$OPENBOX_RC"
fi
# Patch in new theme, larger fonts, big border
sed -i '
  s|<font place="ActiveWindow">.*</font>|<font place="ActiveWindow">Poppins Bold 22</font>|g;
  s|<font place="InactiveWindow">.*</font>|<font place="InactiveWindow">Poppins 18</font>|g;
  s|<font place="MenuHeader">.*</font>|<font place="MenuHeader">Poppins Bold 22</font>|g;
  s|<font place="MenuItem">.*</font>|<font place="MenuItem">Poppins 20</font>|g;
  s|<font place="ActiveOnScreenDisplay">.*</font>|<font place="ActiveOnScreenDisplay">Poppins 26</font>|g;
  s|<font place="InactiveOnScreenDisplay">.*</font>|<font place="InactiveOnScreenDisplay">Poppins 22</font>|g;
' "$OPENBOX_RC"
chown $USERNAME:$USERNAME "$OPENBOX_RC"

# --- Menu.xml (TAOV + admin + Konsole)
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

# --- Custom keybinds for menus, Konsole, etc (touch optimized)
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

# --- Wallpaper (TAOV branded)
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/TAOV-Wallpaper.jpg
chown $USERNAME:$USERNAME "$HOMEDIR/Pictures/taov-wallpaper.jpg"
cat > "$HOMEDIR/.fehbg" <<EOF
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOF
chown $USERNAME:$USERNAME "$HOMEDIR/.fehbg"
chmod 644 "$HOMEDIR/.fehbg"
echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"
chown $USERNAME:$USERNAME "$HOMEDIR/.config/openbox/autostart"

# .xsession (launch Openbox)
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown $USERNAME:$USERNAME "$HOMEDIR/.xsession"

chown -R $USERNAME:$USERNAME "$HOMEDIR"

rm -f "$HOMEDIR/.Xauthority"
chown $USERNAME:$USERNAME "$HOMEDIR"

sudo -u $USERNAME openbox --reconfigure || true

# --- Big system cursor for touch!
echo "Xcursor.size: 48" >> "$HOMEDIR/.Xresources"
chown $USERNAME:$USERNAME "$HOMEDIR/.Xresources"

# --- 13. GRUB splash (after all else)
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
