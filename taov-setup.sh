#!/bin/bash
set -euo pipefail
exec > >(tee /root/taov-setup.log) 2>&1
set -x

USERNAME="till"
HOMEDIR="/home/$USERNAME"
SPP_USER="spp"
SIMPLEPOS_DIR="/opt/spp"
EXT_DST="/opt/chrome-extensions/imagemode"
REPO_DIR="/opt/TAOVLINUX"
POPPINS_DIR="/usr/local/share/fonts/truetype/poppins"

echo "===== TAOV Till Post-Install Setup ====="

# Ensure user exists
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:T@OV2025!" | chpasswd
  usermod -aG sudo "$USERNAME"
fi

# Fonts XML override
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

# Debloat
sed -i '/cdrom:/d' /etc/apt/sources.list
apt-get purge -y libreoffice* gnome* orca* kde* cinnamon* mate* lxqt* lxde* xfce4* task-desktop* task-* lightdm-gtk-greeter || true
apt-get autoremove -y || true
apt-get purge -y google-chrome-stable chromium-browser snapd || true
rm -rf "$HOMEDIR/.config/google-chrome" "$HOMEDIR/.config/chromium" "$HOMEDIR/snap" /snap

# Core packages
apt-get update
apt-get install -y \
  lightdm cups system-config-printer network-manager network-manager-gnome alsa-utils pulseaudio xorg openbox \
  python3 python3-pip python3-venv nano wget curl unzip sudo git xserver-xorg-input-evdev xinput xinput-calibrator \
  mesa-utils feh konsole plank onboard chromium xcursor-themes adwaita-icon-theme-full

systemctl enable cups
systemctl start cups
usermod -aG lpadmin "$USERNAME"

# AnyDesk
set +e
wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | apt-key add -
echo "deb http://deb.anydesk.com/ all main" > /etc/apt/sources.list.d/anydesk.list
apt-get update
apt-get -y install anydesk
set -e

# SimplePOSPrint setup
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

# Chrome extension
mkdir -p "$EXT_DST"
PLUGIN_SRC="$SIMPLEPOS_DIR/plugins/imagemode"
[ -d "$PLUGIN_SRC" ] && cp -r "$PLUGIN_SRC"/* "$EXT_DST"
chown -R $USERNAME:$USERNAME "$EXT_DST"

# LightDM setup
if [ -f /etc/lightdm/lightdm.conf ]; then
  sed -i 's/^#autologin-user=.*/autologin-user=till/' /etc/lightdm/lightdm.conf
  sed -i '/^\[Seat:\*\]/a autologin-user=till\nuser-session=openbox' /etc/lightdm/lightdm.conf || true
fi
ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

# Poppins font
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

# Openbox setup
theme_dir="/usr/share/themes/Arc"
wget -O /tmp/arc-theme.tar.gz https://github.com/jnsh/arc-theme/archive/master.tar.gz
mkdir -p "$theme_dir"
tar -xzf /tmp/arc-theme.tar.gz --strip-components=1 -C "$theme_dir"
cp -r "$theme_dir/Arc-Dark" /usr/share/themes/

mkdir -p "$HOMEDIR/.config/openbox"
cat > "$HOMEDIR/.config/openbox/autostart" <<EOFA
#!/bin/bash
xsetroot -cursor_name left_ptr
export XCURSOR_SIZE=48
onboard &
plank &
[ -f "\$HOME/.fehbg" ] && bash "\$HOME/.fehbg" &
pkill chromium || true
chromium --load-extension=$EXT_DST --kiosk --no-first-run --disable-translate --disable-infobars --disable-session-crashed-bubble \
  "https://aceofvapez.retail.lightspeed.app/" "http://localhost:5000/config.html" &
EOFA
chmod +x "$HOMEDIR/.config/openbox/autostart"

cp /etc/xdg/openbox/rc.xml "$HOMEDIR/.config/openbox/rc.xml"
sed -i 's|<name>.*</name>|<name>Arc-Dark</name>|g' "$HOMEDIR/.config/openbox/rc.xml"
sed -i 's|<font place="ActiveWindow">.*</font>|<font place="ActiveWindow">Poppins Bold 22</font>|g' "$HOMEDIR/.config/openbox/rc.xml"
sed -i 's|<font place="InactiveWindow">.*</font>|<font place="InactiveWindow">Poppins 18</font>|g' "$HOMEDIR/.config/openbox/rc.xml"

cat > "$HOMEDIR/.config/openbox/menu.xml" <<EOMENU
<openbox_menu>
  <menu id="root-menu" label="TAOV Touch">
    <item label="New Lightspeed Tab">
      <action name="Execute">
        <command>chromium --new-window "https://aceofvapez.retail.lightspeed.app/"</command>
      </action>
    </item>
    <item label="SimplePOSPrint Config">
      <action name="Execute">
        <command>chromium "http://localhost:5000/config.html"</command>
      </action>
    </item>
  </menu>
</openbox_menu>
EOMENU

# Hotkeys
awk '/<\/keyboard>/ {
  print "    <keybind key=\"C-A-space\">"
  print "      <action name=\"ShowMenu\">"
  print "        <menu>root-menu</menu>"
  print "      </action>"
  print "    </keybind>"
}1' "$HOMEDIR/.config/openbox/rc.xml" > "$HOMEDIR/.config/openbox/rc.xml.new"
mv "$HOMEDIR/.config/openbox/rc.xml.new" "$HOMEDIR/.config/openbox/rc.xml"

# Wallpaper
mkdir -p "$HOMEDIR/Pictures"
wget -O "$HOMEDIR/Pictures/taov-wallpaper.jpg" https://github.com/Mike-TOAV/TAOVLINUX/raw/main/wallpapers/TAOV-wallpaper.jpg
cat > "$HOMEDIR/.fehbg" <<EOF
feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg
EOF
chmod 644 "$HOMEDIR/.fehbg"
echo "feh --bg-scale \$HOME/Pictures/taov-wallpaper.jpg" >> "$HOMEDIR/.config/openbox/autostart"

# GRUB Splash
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

# Cursor theme
mkdir -p "$HOMEDIR/.icons/default"
cat > "$HOMEDIR/.icons/default/index.theme" <<EOCURSOR
[Icon Theme]
Name=Adwaita
Inherits=Adwaita
EOCURSOR

echo "Xcursor.size: 24" >> "$HOMEDIR/.Xresources"
echo 'export XCURSOR_SIZE=24' >> "$HOMEDIR/.profile"

# Ownership and final
echo "exec openbox-session" > "$HOMEDIR/.xsession"
chmod 755 "$HOMEDIR/.xsession"
chown -R $USERNAME:$USERNAME "$HOMEDIR"
rm -f "$HOMEDIR/.Xauthority"
