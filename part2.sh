#!/bin/bash

set -e

handle_error() {
    echo "Error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

source /etc/profile
export PS1="(chroot) ${PS1}"

mount /dev/nvme0n1p1 /boot

PARTITION_ROOT=$(findmnt -n -o SOURCE /)
PARTITION_BOOT=$(findmnt -n -o SOURCE /boot)

UUID_ROOT=$(blkid -s UUID -o value $PARTITION_ROOT)
UUID_BOOT=$(blkid -s UUID -o value $PARTITION_BOOT)
PARTUUID_ROOT=$(blkid -s PARTUUID -o value $PARTITION)

read -p "Enter the new username: " username
read -p "Enter the new password: " password

emerge-webrsync
emerge --sync --quiet

echo "Europe/Istanbul" > /etc/timezone
emerge --config sys-libs/timezone-data

sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
echo "LC_COLLATE=\"C.UTF-8\"" >> /etc/env.d/02locale

emerge sys-devel/gcc
emerge --autounmask-continue --keep-going --quiet-build --update --complete-graph --deep --newuse --exclude 'sys-devel/gcc sys-libs/timezone-data' -e @world
emerge sys-devel/clang:16/16
emerge sys-devel/clang:15/15
emerge --autounmask-continue --quiet-build dev-vcs/git
emerge --autounmask-continue --quiet-build app-eselect/eselect-repository

eselect repository remove gentoo
rm -r /var/db/repos/gentoo
eselect repository add gentoo git https://github.com/gentoo-mirror/gentoo.git
eselect repository enable wayland-desktop
eselect repository enable guru
eselect repository enable pf4public
eselect repository enable thegreatmcpain
eselect repository add librewolf git https://gitlab.com/librewolf-community/browser/gentoo.git
emaint sync -a

emerge sys-kernel/linux-firmware sys-firmware/intel-microcode app-arch/lz4

sed -i '/^nvidia\/\(tu104\|tu10x\)/!d' /etc/portage/savedconfig/sys-kernel/linux-firmware-*
emerge sys-kernel/linux-firmware

emerge sys-kernel/gentoo-sources

cd /usr/src/linux
make mrproper
curl -sLO https://raw.githubusercontent.com/emrakyz/dotfiles/main/Portage/.config

sed -i -e '/^# *CONFIG_CMDLINE.*/c\' -e "CONFIG_CMDLINE=\"root=PARTUUID=$PARTUUID_ROOT\"" /usr/src/linux/.config

LLVM=1 LLVM_IAS=1 KCFLAGS='-O3 -march=native -mtune=native -fomit-frame-pointer -pipe' KCPPFLAGS='-O3 -march=native -mtune=native -fomit-frame-pointer -pipe' make -j16
cd

mkdir -p /boot/EFI/BOOT
cp /usr/src/linux/arch/x86/boot/bzImage /boot/EFI/BOOT/BOOTX64.EFI

mkdir -p /mnt/harddisk

echo "UUID=$UUID_BOOT /boot vfat defaults,noatime 0 2
UUID=$UUID_ROOT / ext4 defaults,noatime 0 1
UUID=28F03D40F03D1612 /mnt/harddisk ntfs defaults,uid=1000,gid=1000,umask=022,noatime,nofail 0 2" > /etc/fstab

sed -i "s/hostname=.*/hostname=\"$username\"/g" /etc/conf.d/hostname

emerge net-misc/dhcpcd
rc-update add dhcpcd default
rc-service dhcpcd start

echo "127.0.0.1\t$username\tlocalhost
::1\t\t$username\tlocalhost" > /etc/hosts
curl -s https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-gambling-porn-social/hosts | tail -n +40 >> /etc/hosts

sed -i 's/enforce=everyone/enforce=none/g' /etc/security/passwdqc.conf

echo "root:$password" | chpasswd

# sed -i 's/#rc_parallel=\".*\"/rc_parallel=\"YES\"/g' /etc/rc.conf
# sed -i 's/#unicode=\".*\"/unicode=\"YES\"/g' /etc/rc.conf
sed -i 's/clock=.*/clock=\"local\"/g' /etc/conf.d/hwclock

echo "nameserver 9.9.9.9
nameserver 149.112.112.112" > /etc/resolv.conf

echo "nohook resolv.conf" >> /etc/dhcpcd.conf

touch /etc/doas.conf
echo "permit :wheel
permit nopass keepenv :$username
permit nopass keepenv :root" > /etc/doas.conf

USE="-harfbuzz" emerge media-libs/freetype

curl -sLO https://raw.githubusercontent.com/emrakyz/dotfiles/main/dependencies.txt
DEPLIST="`sed -e 's/#.*$//' -e '/^$/d' dependencies.txt | tr '\n' ' '`"
emerge $DEPLIST
rm -rf dependencies.txt

useradd -mG wheel,audio,video,usb,input,portage,pipewire,seat $username
echo "$username:$password" | chpasswd

cd /home/$username
git clone https://github.com/emrakyz/dotfiles.git
cd dotfiles
cp -r .local .config /home/$username
cd ..
rm -rf dotfiles
chmod +x /home/$username/.local/bin/*
chmod +x /home/$username/.config/hypr/start.sh

ln -s /home/$username/.config/shell/profile /home/$username/.zprofile

rc-update add seatd default

chown -R $username:$username /home/$username

chsh --shell /bin/zsh $username
ln -sfT /bin/dash /bin/sh

cd /usr/src/linux
make modules_install
efibootmgr -c -d /dev/nvme0n1 -p 1 -L "Gentoo" -l '\EFI\BOOT\BOOTX64.EFI'

emerge --depclean efibootmgr
emerge --depclean

cd

# remove old modules
cd /lib/modules
ls -1v | head -n -1 | xargs rm -rf
cd

# remove temporary files
rm -rf /var/tmp/portage/*
rm -rf /var/cache/distfiles/*
rm -rf /var/cache/binpkgs/*

# remove cache
rm -rf /home/$username/.cache
mkdir -p /home/$username/.cache/zsh
chown $username:$username /home/$username/.cache
touch /home/$username/.cache/zsh/history

mkdir -p /home/$username/.cache/zsh
touch /home/$username/.cache/zsh/history
cd
git clone https://github.com/zdharma-continuum/fast-syntax-highlighting
mv fast-syntax-highlighting /home/$username/.config/zsh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ./powerlevel10k
mv powerlevel10k /home/$username/.config/zsh

echo "nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm" > video.conf
mkdir -p /etc/modules-load.d
mv video.conf /etc/modules-load.d

python -m venv /home/$username/.local/pyenv

pip3 install pywal --user --break-system-packages
pip3 install pillow --user --break-system-packages
pip3 install PyGObject --user --break-system-packages 
pip3 install wpgtk --user --break-system-packages
pip3 install gallery-dl --user --break-system-packages
pip3 install yt-dlp --user --break-system-packages

#gsettings set org.gnome.desktop.interface cursor-theme Breeze_Snow
#gsettings set org.gnome.desktop.interface cursor-size 18
#gsettings set org.gnome.desktop.interface font-antialiasing rgba
#gsettings set org.gnome.desktop.interface font-name 'Liberation Sans 11'
#gsettings set org.gnome.desktop.interface font-hinting full
#gsettings set org.gnome.desktop.interface gtk-theme Sweet-Dark
#gsettings set org.gnome.desktop.interface icon-theme breeze-dark
#gsettings set org.gnome.desktop.interface toolbar-style text
#gsettings set org.gtk.Settings.FileChooser sort-directories-first true
#gsettings set org.gnome.desktop.interface toolbar-icons-size small

eselect fontconfig disable 10-hinting-slight.conf
eselect fontconfig disable 10-no-antialias.conf
eselect fontconfig disable 10-sub-pixel-none.conf
eselect fontconfig enable 10-hinting-full.conf
eselect fontconfig enable 10-sub-pixel-rgb.conf
eselect fontconfig enable 10-yes-antialias.conf
eselect fontconfig enable 11-lcdfilter-default.conf

curl -sLO https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz
tar -xzf install-tl-unx.tar.gz
cd install-tl-20*
curl -sLO https://raw.githubusercontent.com/emrakyz/dotfiles/main/texlive.profile
./install-tl -profile texlive.profile
tlmgr install apa7 biber biblatex geometry scalerel times
cd
rm -rf install-tl-unx.tar.gz install-tl-20*

doas -u "$username" librewolf --headless >/dev/null 2>&1 &
sleep 3
killall librewolf
profile_dir=$(sed -n "/Default=.*.default-release/ s/.*=//p" /home/$username/.librewolf/profiles.ini)
cd /home/$username/.librewolf/$profile_dir
mkdir chrome
curl -sLO https://raw.githubusercontent.com/arkenfox/user.js/master/user.js
curl -sLO https://raw.githubusercontent.com/emrakyz/dotfiles/main/user-overrides.js
curl -sLO https://raw.githubusercontent.com/arkenfox/user.js/master/updater.sh
chmod +x updater.sh
chown -R $username:$username /home/$username/.librewolf
doas -u "$username" ./updater.sh -s -u
cd chrome
curl -sLO https://raw.githubusercontent.com/emrakyz/dotfiles/main/userChrome.css
cd

ext_dir="/home/$username/.librewolf/$profile_dir/extensions"
mkdir -p "$ext_dir"
addon_names=("ublock-origin" "istilldontcareaboutcookies" "libredirect" "custom-scrollbars" "vimium-ff" "chat-gpt-long-text-input" "i-auto-fullscreen")

for addon_name in "${addon_names[@]}"
do
  addonurl="$(curl --silent "https://addons.mozilla.org/en-US/firefox/addon/${addon_name}/" | grep -o 'https://addons.mozilla.org/firefox/downloads/file/[^"]*')"

  curl -sL "$addonurl" -o extension.xpi

  ext_id=$(unzip -p extension.xpi manifest.json | grep "\"id\"")
  ext_id="${ext_id%\"*}"
  ext_id="${ext_id##*\"}"

  mv extension.xpi "$ext_dir/$ext_id.xpi"
done

doas -u "$username" env CGO_ENABLED=0 go install -ldflags="-s -w" github.com/gokcehan/lf@latest
cp /home/$username/go/bin/lf /usr/bin/
rm -rf /home/$username/go

git clone https://raw.githubusercontent.com/emrakyz/dotfiles/main/my-ublock-backup_2023-05-27_14.15.29.txt

echo "====GENTOO INSTALLATION COMPLETED SUCCESSFULLY===="
