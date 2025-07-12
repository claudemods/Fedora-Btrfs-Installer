#!/bin/bash
# Fedora UEFI-only BTRFS Installation with Multiple Desktop Options
set -e

# Install dialog if missing
if ! command -v dialog >/dev/null; then
    dnf install -y dialog >/dev/null 2>&1
fi

# Colors
RED='\033[38;2;255;0;0m'
CYAN='\033[38;2;0;255;255m'
NC='\033[0m'

show_ascii() {
    clear
    echo -e "${RED}░█████╗░██╗░░░░░░█████╗░██║░░░██╗██████╗░███████╗███╗░░░███╗░█████╗░██████╗░░██████╗
██╔══██╗██║░░░░░██╔══██╗██║░░░██║██╔══██╗██╔════╝████╗░████║██╔══██╗██╔══██╗██╔════╝
██║░░╚═╝██║░░░░░███████║██║░░░██║██║░░██║█████╗░░██╔████╔██║██║░░██║██║░░██║╚█████╗░
██║░░██╗██║░░░░░██╔══██║██║░░░██║██║░░██║██╔══╝░░██║╚██╔╝██║██║░░██║██║░░██║░╚═══██╗
╚█████╔╝███████╗██║░░██║╚██████╔╝██████╔╝███████╗██║░╚═╝░██║╚█████╔╝██████╔╝██████╔╝
░╚════╝░╚══════╝╚═╝░░╚═╝░╚═════╝░╚═════╝░╚══════╝╚═╝░░░░░╚═╝░╚════╝░╚═════╝░╚═════╝░${NC}"
    echo -e "${CYAN}Fedora Btrfs Installer v1.0 12-07-2025${NC}"
    echo
}

cyan_output() {
    "$@" | while IFS= read -r line; do echo -e "${CYAN}$line${NC}"; done
}

configure_fastest_mirrors() {
    show_ascii
    dialog --title "Fastest Mirrors" --yesno "Would you like to find and use the fastest mirrors?" 7 50
    response=$?
    case $response in
        0) 
            echo -e "${CYAN}Finding fastest mirrors...${NC}"
            dnf install -y fastestmirror >/dev/null 2>&1
            sed -i 's/^#baseurl/baseurl/' /etc/yum.repos.d/fedora.repo
            sed -i 's/^metalink/#metalink/' /etc/yum.repos.d/fedora.repo
            echo -e "${CYAN}Mirrorlist updated with fastest mirrors${NC}"
            ;;
        1) 
            echo -e "${CYAN}Using default mirrors${NC}"
            ;;
        255) 
            echo -e "${CYAN}Using default mirrors${NC}"
            ;;
    esac
}

perform_installation() {
    show_ascii
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${CYAN}This script must be run as root or with sudo${NC}"
        exit 1
    fi
    if [ ! -d /sys/firmware/efi ]; then
        echo -e "${CYAN}ERROR: This script requires UEFI boot mode${NC}"
        exit 1
    fi
    echo -e "${CYAN}About to install to $TARGET_DISK with these settings:"
    echo "Hostname: $HOSTNAME"
    echo "Timezone: $TIMEZONE"
    echo "Keymap: $KEYMAP"
    echo "Username: $USER_NAME"
    echo "Desktop: $DESKTOP_ENV"
    echo "Kernel: $KERNEL_TYPE"
    echo "Bootloader: $BOOTLOADER"
    echo "Repositories: ${REPOS[@]}"
    echo "Compression Level: $COMPRESSION_LEVEL${NC}"
    echo -ne "${CYAN}Continue? (y/n): ${NC}"
    read confirm
    if [ "$confirm" != "y" ]; then
        echo -e "${CYAN}Installation cancelled.${NC}"
        exit 1
    fi

    # Partitioning
    cyan_output parted -s "$TARGET_DISK" mklabel gpt
    cyan_output parted -s "$TARGET_DISK" mkpart primary 1MiB 513MiB
    cyan_output parted -s "$TARGET_DISK" set 1 esp on
    cyan_output parted -s "$TARGET_DISK" mkpart primary 513MiB 100%

    # Formatting
    cyan_output mkfs.vfat -F32 "${TARGET_DISK}1"
    cyan_output mkfs.btrfs -f "${TARGET_DISK}2"

    # Mounting and subvolumes
    cyan_output mount "${TARGET_DISK}2" /mnt
    cyan_output btrfs subvolume create /mnt/@
    cyan_output btrfs subvolume create /mnt/@home
    cyan_output btrfs subvolume create /mnt/@root
    cyan_output btrfs subvolume create /mnt/@srv
    cyan_output btrfs subvolume create /mnt/@tmp
    cyan_output btrfs subvolume create /mnt/@log
    cyan_output btrfs subvolume create /mnt/@cache
    cyan_output umount /mnt

    # Remount with compression
    cyan_output mount -o subvol=@,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt
    cyan_output mkdir -p /mnt/boot/efi
    cyan_output mount "${TARGET_DISK}1" /mnt/boot/efi
    cyan_output mkdir -p /mnt/home
    cyan_output mkdir -p /mnt/root
    cyan_output mkdir -p /mnt/srv
    cyan_output mkdir -p /mnt/tmp
    cyan_output mkdir -p /mnt/var/cache
    cyan_output mkdir -p /mnt/var/log
    cyan_output mount -o subvol=@home,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt/home
    cyan_output mount -o subvol=@root,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt/root
    cyan_output mount -o subvol=@srv,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt/srv
    cyan_output mount -o subvol=@tmp,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt/tmp
    cyan_output mount -o subvol=@log,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt/var/log
    cyan_output mount -o subvol=@cache,compress=zstd:$COMPRESSION_LEVEL,compress-force=zstd:$COMPRESSION_LEVEL "${TARGET_DISK}2" /mnt/var/cache

    # Determine kernel package based on selection
    case "$KERNEL_TYPE" in
        "Standard") KERNEL_PKG="kernel" ;;
        "LTS") KERNEL_PKG="kernel-lts" ;;
        "Realtime") KERNEL_PKG="kernel-rt" ;;
    esac

    # Base packages based on bootloader selection
    BASE_PKGS="@core $KERNEL_PKG btrfs-progs nano"
    case "$BOOTLOADER" in
        "GRUB") BASE_PKGS="$BASE_PKGS grub2 efibootmgr dosfstools" ;;
        "systemd-boot") BASE_PKGS="$BASE_PKGS systemd-boot" ;;
    esac

    # Add selected repositories
    for repo in "${REPOS[@]}"; do
        case "$repo" in
            "multilib")
                echo -e "${CYAN}Enabling multilib repository...${NC}"
                dnf config-manager --set-enabled fedora-multilib >/dev/null 2>&1
                ;;
            "testing")
                echo -e "${CYAN}Enabling testing repository...${NC}"
                dnf config-manager --set-enabled updates-testing >/dev/null 2>&1
                ;;
            "community-testing")
                echo -e "${CYAN}Enabling community-testing repository...${NC}"
                dnf config-manager --set-enabled updates-testing-modular >/dev/null 2>&1
                ;;
        esac
    done

    # Generate fstab
    echo -e "${CYAN}Generating fstab with BTRFS subvolumes...${NC}"
    ROOT_UUID=$(blkid -s UUID -o value "${TARGET_DISK}2")
    {
        echo ""
        echo "# Btrfs subvolumes (auto-added)"
        echo "UUID=$ROOT_UUID /              btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@ 0 0"
        echo "UUID=$ROOT_UUID /root          btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@root 0 0"
        echo "UUID=$ROOT_UUID /home          btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@home 0 0"
        echo "UUID=$ROOT_UUID /srv           btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@srv 0 0"
        echo "UUID=$ROOT_UUID /var/cache     btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@cache 0 0"
        echo "UUID=$ROOT_UUID /var/tmp       btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@tmp 0 0"
        echo "UUID=$ROOT_UUID /var/log       btrfs   rw,noatime,compress=zstd:$COMPRESSION_LEVEL,discard=async,space_cache=v2,subvol=/@log 0 0"
    } > /mnt/etc/fstab

    # Install base system
    dnf --installroot=/mnt install -y $BASE_PKGS >/dev/null 2>&1

    # Chroot setup
    cat << CHROOT | tee /mnt/setup-chroot.sh >/dev/null
#!/bin/bash
# Basic system configuration
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
# Users and passwords
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USER_NAME"
echo "$USER_NAME:$USER_PASSWORD" | chpasswd
# Configure sudo
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
# Handle bootloader installation
case "$BOOTLOADER" in
    "GRUB")
        grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=FEDORA
        grub2-mkconfig -o /boot/grub2/grub.cfg
        ;;
    "systemd-boot")
        bootctl --path=/boot/efi install
        mkdir -p /boot/efi/loader/entries
        cat > /boot/efi/loader/loader.conf << 'LOADER'
default fedora
timeout 3
editor  yes
LOADER
        cat > /boot/efi/loader/entries/fedora.conf << 'ENTRY'
title   Fedora
linux   /vmlinuz-$KERNEL_PKG
initrd  /initramfs-$KERNEL_PKG.img
options root=UUID=$ROOT_UUID rootflags=subvol=@ rw
ENTRY
        ;;
esac
# Install desktop environment and related packages only if selected
case "$DESKTOP_ENV" in
    "GNOME")
        dnf install -y @gnome-desktop gnome-terminal firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable gdm
        ;;
    "KDE Plasma")
        dnf install -y @kde-desktop plasma-discover dolphin konsole firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable sddm
        ;;
    "XFCE")
        dnf install -y @xfce-desktop xfce4-goodies lightdm lightdm-gtk-greeter mousepad xfce4-terminal firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "MATE")
        dnf install -y @mate-desktop mate-media lightdm lightdm-gtk-greeter pluma mate-terminal firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "LXQt")
        dnf install -y @lxqt-desktop breeze-icons sddm qterminal firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable sddm
        ;;
    "Cinnamon")
        dnf install -y @cinnamon-desktop cinnamon-translations lightdm lightdm-gtk-greeter xed gnome-terminal firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "Budgie")
        dnf install -y @budgie-desktop budgie-extras gnome-control-center gnome-terminal lightdm lightdm-gtk-greeter firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "Deepin")
        dnf install -y @deepin-desktop deepin-extra lightdm deepin-terminal firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "i3")
        dnf install -y i3-wm i3status i3lock dmenu lightdm lightdm-gtk-greeter alacritty firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "Sway")
        dnf install -y sway swaylock swayidle waybar wofi lightdm lightdm-gtk-greeter foot firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        ;;
    "Hyprland")
        dnf install -y hyprland waybar rofi wofi kitty swaybg swaylock-effects wl-clipboard lightdm lightdm-gtk-greeter firefox pulseaudio pavucontrol >/dev/null 2>&1
        systemctl enable lightdm
        # Create Hyprland config directory
        mkdir -p /home/$USER_NAME/.config/hypr
        cat > /home/$USER_NAME/.config/hypr/hyprland.conf << 'HYPRCONFIG'
# This is a basic Hyprland config
exec-once = waybar &
exec-once = swaybg -i ~/wallpaper.jpg &
monitor=,preferred,auto,1
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = yes
    }
}
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
}
decoration {
    rounding = 5
    blur = yes
    blur_size = 3
    blur_passes = 1
    blur_new_optimizations = on
}
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 7, myBezier
    animation = windowsOut, 1, 7, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 7, default
    animation = workspaces, 1, 6, default
}
dwindle {
    pseudotile = yes
    preserve_split = yes
}
master {
    new_is_master = true
}
bind = SUPER, Return, exec, kitty
bind = SUPER, Q, killactive,
bind = SUPER, M, exit,
bind = SUPER, V, togglefloating,
bind = SUPER, F, fullscreen,
bind = SUPER, D, exec, rofi -show drun
bind = SUPER, P, pseudo,
bind = SUPER, J, togglesplit,
HYPRCONFIG
        # Set ownership of config files
        chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.config
        ;;
    "None")
        # Install nothing extra for minimal system
        echo "No desktop environment selected - minimal installation"
        ;;
esac
# Enable TRIM for SSDs
systemctl enable fstrim.timer
# Clean up
rm /setup-chroot.sh
CHROOT
    chmod +x /mnt/setup-chroot.sh
    chroot /mnt /setup-chroot.sh
    umount -R /mnt
    echo -e "${CYAN}Installation complete!${NC}"
    # Post-install dialog menu
    while true; do
        choice=$(dialog --clear --title "Installation Complete" \
                       --menu "Select post-install action:" 12 45 5 \
                       1 "Reboot now" \
                       2 "Chroot into installed system" \
                       3 "Exit without rebooting" \
                       3>&1 1>&2 2>&3)
        case $choice in
            1) 
                clear
                echo -e "${CYAN}Rebooting system...${NC}"
                reboot
                ;;
            2)
                clear
                echo -e "${CYAN}Entering chroot...${NC}"
                mount "${TARGET_DISK}1" /mnt/boot/efi
                mount -o subvol=@ "${TARGET_DISK}2" /mnt
                mount -t proc none /mnt/proc
                mount --rbind /dev /mnt/dev
                mount --rbind /sys /mnt/sys
                mount --rbind /dev/pts /mnt/dev/pts
                chroot /mnt /bin/bash
                umount -R /mnt
                ;;
            3)
                clear
                exit 0
                ;;
            *)
                echo -e "${CYAN}Invalid option selected${NC}"
                ;;
        esac
    done
}

configure_installation() {
    TARGET_DISK=$(dialog --title "Target Disk" --inputbox "Enter target disk (e.g. /dev/sda):" 8 40 3>&1 1>&2 2>&3)
    HOSTNAME=$(dialog --title "Hostname" --inputbox "Enter hostname:" 8 40 3>&1 1>&2 2>&3)
    TIMEZONE=$(dialog --title "Timezone" --inputbox "Enter timezone (e.g. America/New_York):" 8 40 3>&1 1>&2 2>&3)
    KEYMAP=$(dialog --title "Keymap" --inputbox "Enter keymap (e.g. us):" 8 40 3>&1 1>&2 2>&3)
    USER_NAME=$(dialog --title "Username" --inputbox "Enter username:" 8 40 3>&1 1>&2 2>&3)
    USER_PASSWORD=$(dialog --title "User Password" --passwordbox "Enter user password:" 8 40 3>&1 1>&2 2>&3)
    ROOT_PASSWORD=$(dialog --title "Root Password" --passwordbox "Enter root password:" 8 40 3>&1 1>&2 2>&3)
    # Kernel selection
    KERNEL_TYPE=$(dialog --title "Kernel Selection" --menu "Select kernel:" 15 40 3 \
        "Standard" "Standard Fedora kernel" \
        "LTS" "Long-term support kernel" \
        "Realtime" "Real-time kernel" 3>&1 1>&2 2>&3)
    # Bootloader selection
    BOOTLOADER=$(dialog --title "Bootloader Selection" --menu "Select bootloader:" 15 40 2 \
        "GRUB" "GRUB (recommended for most users)" \
        "systemd-boot" "Minimal systemd-boot" 3>&1 1>&2 2>&3)
    # Repository selection
    REPOS=()
    repo_options=()
    repo_status=()
    # Check current repo status in dnf.conf to set defaults
    if dnf repolist enabled | grep -q "fedora-multilib"; then
        repo_status+=("on")
    else
        repo_status+=("off")
    fi
    repo_options+=("multilib" "32-bit software support" ${repo_status[0]})
    if dnf repolist enabled | grep -q "updates-testing"; then
        repo_status+=("on")
    else
        repo_status+=("off")
    fi
    repo_options+=("testing" "Testing repository" ${repo_status[1]})
    if dnf repolist enabled | grep -q "updates-testing-modular"; then
        repo_status+=("on")
    else
        repo_status+=("off")
    fi
    repo_options+=("community-testing" "Community testing repository" ${repo_status[2]})
    REPOS=($(dialog --title "Additional Repositories" --checklist "Enable additional repositories:" 15 50 5 \
        "${repo_options[@]}" 3>&1 1>&2 2>&3))
    DESKTOP_ENV=$(dialog --title "Desktop Environment" --menu "Select desktop:" 20 50 12 \
        "GNOME" "GNOME Desktop (gnome)" \
        "KDE Plasma" "KDE Plasma Desktop (plasma-desktop)" \
        "XFCE" "XFCE Desktop (xfce4)" \
        "MATE" "MATE Desktop (mate)" \
        "LXQt" "LXQt Desktop (lxqt)" \
        "Cinnamon" "Cinnamon Desktop (cinnamon)" \
        "Budgie" "Budgie Desktop (budgie-desktop)" \
        "Deepin" "Deepin Desktop (deepin)" \
        "i3" "i3 Window Manager (i3-wm)" \
        "Sway" "Sway Wayland Compositor (sway)" \
        "Hyprland" "Hyprland Wayland Compositor (hyprland)" \
        "None" "No desktop environment (minimal install)" 3>&1 1>&2 2>&3)
    COMPRESSION_LEVEL=$(dialog --title "Compression Level" --inputbox "Enter BTRFS compression level (0-22, default is 3):" 8 40 3 3>&1 1>&2 2>&3)
    # Validate compression level
    if ! [[ "$COMPRESSION_LEVEL" =~ ^[0-9]+$ ]] || [ "$COMPRESSION_LEVEL" -lt 0 ] || [ "$COMPRESSION_LEVEL" -gt 22 ]; then
        dialog --msgbox "Invalid compression level. Using default (3)." 6 40
        COMPRESSION_LEVEL=3
    fi
}

main_menu() {
    while true; do
        choice=$(dialog --clear --title "Fedora Btrfs Installer v1.0 12-07-2025" \
                       --menu "Select option:" 15 45 6 \
                       1 "Configure Installation" \
                       2 "Find Fastest Mirrors" \
                       3 "Start Installation" \
                       4 "Exit" 3>&1 1>&2 2>&3)
        case $choice in
            1) configure_installation ;;
            2) configure_fastest_mirrors ;;
            3)
                if [ -z "$TARGET_DISK" ]; then
                    dialog --msgbox "Please configure installation first!" 6 40
                else
                    perform_installation
                fi
                ;;
            4) clear; exit 0 ;;
        esac
    done
}

show_ascii
main_menu
