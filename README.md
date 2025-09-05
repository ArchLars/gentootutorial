# Gentoo Linux Install Guide (KDE Plasma + Wayland + NVIDIA, systemd, systemd‑boot, GPT auto, dracut, binary‑first)

## Partitioning strategy

Two partitions only, both GPT:

1) **EFI System Partition** 1 GiB

2) **Root** the rest

No swap partition. We use zswap (in‑kernel compressed swap cache) instead. You can add a swapfile later if desired.

We depend on **systemd‑gpt‑auto‑generator** to discover root. That means we must set the **type GUIDs** correctly:

- EFI System Partition: `c12a7328‑f81f‑11d2‑ba4b‑00a0c93ec93b` (aka code `EF00` in `sgdisk`)
- x86‑64 Linux Root: `4f68bce3‑e8cd‑4db1‑96e7‑fbcaf984b709` (aka code `8304` in `sgdisk`)

> If you are on BIOS or a different architecture, this guide does not apply as written. Use UEFI with GPT.

---

## Step 0, Boot and prep the live environment

Boot the **Gentoo minimal amd64 ISO** in UEFI mode. Ensure you have network.

```bash
# Optional, set keymap temporarily
loadkeys no

# Confirm disk name
lsblk -e7

# Sync clock over network (helps with SSL)
ntpd -qg -x -n -p pool.ntp.org || true
```

---

## Step 1, Partition the disk (EFI + root with correct GUID types)

**Warning** this erases the target disk.

```bash
d=/dev/nvme0n1

# Zap and create GPT
sgdisk --zap-all "$d"
sgdisk -o "$d"

# 1: EFI 1GiB, 2: Root rest of disk
sgdisk -n1:0:+1GiB -t1:EF00 -c1:EFI "$d"
sgdisk -n2:0:0     -t2:8304 -c2:root "$d"

# Print result
sgdisk -p "$d"
```

Format and mount:

```bash
mkfs.fat -F32 -n EFI  ${d}p1
mkfs.ext4 -L root     ${d}p2

mount ${d}p2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot
mount ${d}p1 /mnt/gentoo/boot
```

> We deliberately do not create `/home`. GPT auto can also handle `/home` and other mount points by GUID, but we keep it minimal like the Arch guide.

---

## Step 2, Stage3 (systemd variant), Portage, mirrors

Download the latest **stage3‑amd64‑systemd** tarball and unpack it into `/mnt/gentoo`. Use a local mirror for speed.

```bash
cd /mnt/gentoo
# Pick a mirror you like, then:
wget -O stage3.tar.xz "$(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt | awk '/xz/{print "https://distfiles.gentoo.org/releases/amd64/autobuilds/"$1; exit}')"

# Optionally fetch the DIGESTS and verify here
# wget DIGESTS, gpg --keyserver hkps://keys.openpgp.org --recv-keys 0xBB572E0E2D182910 ...

# Unpack (preserves xattrs, devices)
tar xpf stage3.tar.xz --xattrs-include='*' --numeric-owner
```

Copy DNS and mount special filesystems for the chroot:

```bash
cp --dereference /etc/resolv.conf etc/
mount -t proc /proc proc
mount --rbind /sys sys && mount --make-rslave sys
mount --rbind /dev dev && mount --make-rslave dev
```

Chroot:

```bash
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(gentoo-chroot) $PS1"
```

Sync Portage tree and install helper tools:

```bash
emerge-webrsync     # fast first sync without full git
emaint sync -r gentoo
emerge --ask app-portage/gentoolkit app-portage/mirrorselect
```

Pick fast distfile mirrors:

```bash
mirrorselect -i -o >> /etc/portage/make.conf
```

---

## Step 3, Binary packages first (binrepos)

Enable official Gentoo binary hosts. For a 7800X3D, use the **x86‑64‑v3** set.

```bash
mkdir -p /etc/portage/binrepos.conf
cat > /etc/portage/binrepos.conf/gentoobinhost.conf << 'EOF'
[gentoo]
priority = 90
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/17.1/x86-64-v3/
EOF

# Prefer binpkgs, but fall back to source when missing
echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --binpkg-respect-use=y --with-bdeps=y"' >> /etc/portage/make.conf
```

> You can switch to baseline `x86-64` if you hit a missing package on v3, then switch back. Portage will mix binary and source installs as needed.

---

## Step 4, Profile, USE flags, VIDEO_CARDS

Select a **systemd desktop Plasma** profile for a Wayland desktop and good defaults.

```bash
eselect profile list
# Pick the latest "amd64/17.1/desktop/plasma/systemd" entry (number X)
eselect profile set X
```

Set global USE features for Wayland desktop and NVIDIA, then refresh environment:

```bash
cat >> /etc/portage/make.conf << 'EOF'
# Graphics stack and desktop
VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"

# Common toggles for a modern desktop
USE="alsa bluetooth dbus egl elogind? - wayland vulkan pipewire pulseaudio udev X kde plasma sddm qt5 qt6 opengl -gtk -gnome"

# ABI for Steam and 32-bit NV libs (profile handles multilib, this is just explicit)
ABI_X86="64 32"

# Optional, keep CFLAGS modest since we are mostly using binpkgs
CFLAGS="-O2 -pipe"
CXXFLAGS="${CFLAGS}"
MAKEOPTS="-j16"
EOF

env-update && source /etc/profile
```

> If you truly have a working iGPU as well, add `amdgpu` to `VIDEO_CARDS`. The 7800X3D typically has no active iGPU, so `nvidia` alone is appropriate.

---

## Step 5, Core system and kernel (distribution kernel, dracut, systemd‑boot integration)

Install firmware, prebuilt kernel, dracut, and the installkernel framework with systemd‑boot and dracut integration.

```bash
emerge --ask \
  sys-kernel/linux-firmware \
  sys-kernel/gentoo-kernel-bin \
  sys-kernel/dracut \
  sys-kernel/installkernel
```

Enable the correct installkernel features so kernel updates add loader entries and an initramfs automatically:

```bash
mkdir -p /etc/portage/package.use
cat > /etc/portage/package.use/installkernel << 'EOF'
sys-kernel/installkernel systemd systemd-boot dracut
EOF

emerge --ask --newuse sys-kernel/installkernel
```

Create a kernel command line file used by `kernel-install` for new entries. We keep it simple, no `root=` parameter is provided so GPT auto will discover the root partition by GUID.

```bash
cat > /etc/kernel/cmdline << 'EOF'
quiet loglevel=3 splash
nvidia_drm.modeset=1
zswap.enabled=1 zswap.max_pool_percent=25
EOF
```

Configure dracut to include the NVIDIA kernel modules in the initramfs so Wayland modesetting is ready early.

```bash
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/10-nvidia.conf << 'EOF'
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
EOF
```

> When `gentoo-kernel-bin` gets upgraded, `kernel-install` will regenerate the initramfs with dracut and write a new loader entry automatically. You can trigger it manually for the current kernel with `kernel-install add $(uname -r) /usr/lib/modules/$(uname -r)/vmlinuz` if you wish.

---

## Step 6, systemd‑boot setup (no fstab, GPT auto)

`/boot` is already the mounted ESP. Install the boot manager and verify loader directory layout.

```bash
bootctl --esp-path=/boot install

# Loader defaults
mkdir -p /boot/loader
cat > /boot/loader/loader.conf << 'EOF'
default gentoo
timeout 3
console-mode max
editor no
EOF
```

You do not need to write a manual entry for each kernel, `sys-kernel/installkernel` plus `kernel-install` will do it. A stub entry can be created initially if desired:

```bash
mkdir -p /boot/loader/entries
cat > /boot/loader/entries/gentoo.conf << 'EOF'
title   Gentoo Linux (autodiscovered root)
linux   /vmlinuz
initrd  /initramfs
options $kernelopts
EOF
```

- We intentionally omit `root=` in `options`. The **systemd GPT auto generator** will mount the first x86‑64 root partition on the same disk as the ESP because we set the correct type GUIDs.
- If you ever want a home partition later, give it the `home` type GUID and it will be mounted automatically too.

---

## Step 7, Base system settings

```bash
# Timezone and clock
ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
hwclock --systohc

# Locales (example: en_US and nb_NO)
cat > /etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
nb_NO.UTF-8 UTF-8
EOF
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

# Hostname and hosts
echo 'mybox' > /etc/hostname
cat > /etc/hosts << 'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   mybox
EOF

# Root password
passwd

# User
useradd -m -G wheel,video,audio,plugdev,lp,storage -s /bin/zsh lars
passwd lars

# Allow wheel to sudo
emerge --ask app-admin/sudo
sed -i 's/^# %wheel/%wheel/' /etc/sudoers
```

---

## Step 8, Networking, firewall, power tools

```bash
emerge --ask net-misc/networkmanager net-firewall/firewalld sys-power/cpupower

systemctl enable NetworkManager.service
systemctl enable firewalld.service
# Optional weekly TRIM for SSDs
systemctl enable fstrim.timer
```

---

## Step 9, NVIDIA proprietary driver for Wayland

Install the driver with Wayland support and related bits. Gentoo’s ebuilds provide GBM and the Wayland EGL platform.

```bash
emerge --ask x11-drivers/nvidia-drivers gui-libs/egl-wayland
```

Set the kernel module to use DRM modeset early (we already pass `nvidia_drm.modeset=1` in `/etc/kernel/cmdline`). No Xorg config is required for Wayland on Plasma. If you will also use Xorg apps, the GLVND stack is used automatically.

> If you truly have an AMD iGPU you want to use, add `amdgpu` to `VIDEO_CARDS` then `emerge --changed-use --deep @world`. Hybrid setups on Wayland are possible via KWin and GBM. Most 7800X3D builds do not expose an iGPU, so keep it simple.

Rebuild initramfs to ensure the modules are present now:

```bash
dracut --force /boot/initramfs $(uname -r)
```

---

## Step 10, PipeWire audio (with WirePlumber)

```bash
emerge --ask media-video/pipewire media-video/wireplumber

# Enable user services (recommended)
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service
```

> The `sound-server` USE on PipeWire controls whether it acts as the PulseAudio replacement. The Plasma profile and our USE set cover this in most cases.

---

## Step 11, KDE Plasma 6, SDDM, Wayland

Install the desktop meta, SDDM, and a few KDE apps matching the original list.

```bash
emerge --ask \
  kde-plasma/plasma-meta x11-misc/sddm \
  kde-apps/dolphin kde-apps/konsole x11-terms/kitty \
  kde-apps/kdegraphics-thumbnailers kde-apps/ffmpegthumbs \
  kde-plasma/kdeplasma-addons kde-apps/kio-extras

# Enable graphical login
systemctl enable sddm.service
```

> SDDM runs Wayland sessions fine on Plasma 6. You can pick “Plasma (Wayland)” on the login screen.

Optional KDE apps from the list:

```bash
emerge --ask kde-apps/kate kde-apps/gwenview kde-apps/ark
```

---

## Step 12, Browsers, mail, terminals

Prefer official binaries for speed:

```bash
emerge --ask www-client/firefox-bin mail-client/thunderbird-bin
```

Terminal and fetch tool:

```bash
emerge --ask x11-terms/kitty app-misc/fastfetch
```

Zsh and extras:

```bash
emerge --ask app-shells/zsh app-shells/zsh-autosuggestions app-shells/zsh-syntax-highlighting
# oh-my-zsh lives in the GURU overlay as app-shells/ohmyzsh
```

---

## Step 13, Gaming stack

**Steam** usually lives in the steam overlay. Add overlays with `eselect repository`:

```bash
emerge --ask dev-vcs/git app-eselect/eselect-repository
eselect repository enable steam-overlay
emaint sync -r steam-overlay

# Steam
emerge --ask games-util/steam-launcher

# DXVK and Lutris (DXVK is in the main tree)
emerge --ask app-emulation/dxvk games-util/lutris

# Proton GE helper (GURU overlay)
eselect repository enable guru
emaint sync -r guru
emerge --ask games-util/protonup-qt

# CUDA toolkit if needed for compute
emerge --ask dev-util/nvidia-cuda-toolkit
```

> Ensure your profile is multilib so 32‑bit libraries are available. The Desktop Plasma systemd profile is multilib by default. For DXVK you usually do not need the `-bin` variant.

---

## Step 14, Networking niceties and firewall

```bash
nmcli device status   # quick check
firewall-cmd --state  # should be running
```

Optional Plasma firewall settings applet:

```bash
emerge --ask kde-plasma/plasma-firewall
```

---

## Step 15, Final touches, rebuild world if USE changed

Any time you change `VIDEO_CARDS`, `USE`, or overlays, run:

```bash
emerge --ask --update --deep --newuse @world
```

Clean up and regenerate initramfs if you changed driver modules:

```bash
dracut --force /boot/initramfs $(uname -r)
```

Enable periodic services and power tools:

```bash
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd.service
systemctl enable cpupower.service || true
```

Rebuild kernel entries if needed, then exit, unmount, and reboot:

```bash
exit
umount -R /mnt/gentoo
reboot
```

---

## Post‑install quick checks

- `bootctl status` shows the loader and entries.
- `lsblk` shows `/` mounted from the partition with type `8304`.
- `cat /proc/cmdline` includes `nvidia_drm.modeset=1` and zswap options, but no `root=`.
- `systemctl --user status pipewire` is active for your user.
- `kwin_wayland --replace` works if you ever test KWin directly.

---

## Package mapping from those familiar with Arch to Gentoo

**Core System and Boot**

- `systemd-boot` → `sys-apps/systemd` provides `bootctl` (or `sys-apps/systemd-utils` on OpenRC only hosts)
- `linux-firmware` → `sys-kernel/linux-firmware` (includes AMD CPU microcode files)
- `mkinitcpio` → `sys-kernel/dracut`
- `base-devel` → use `@system` plus `app-portage/gentoolkit`
- `reflector` → use `app-portage/mirrorselect`

**Desktop and Display**

- `plasma-meta` → `kde-plasma/plasma-meta`
- `sddm` → `x11-misc/sddm`
- `dolphin` → `kde-apps/dolphin`
- `konsole` → `kde-apps/konsole`
- `kitty` → `x11-terms/kitty`
- `kdegraphics-thumbnailers` → `kde-apps/kdegraphics-thumbnailers`
- `ffmpegthumbs` → `kde-apps/ffmpegthumbs`
- `kdeplasma-addons` → `kde-plasma/kdeplasma-addons`
- `kio-admin` → provided by `kde-apps/kio-extras`

**Graphics and Drivers**

- `nvidia-open-dkms`, `nvidia-utils`, `lib32-nvidia-utils` → `x11-drivers/nvidia-drivers` (enable multilib by using a multilib profile)

**Audio**

- `pipewire`, `pipewire-alsa/pulse/jack` → `media-video/pipewire` with appropriate USE, plus `media-video/wireplumber`

**Network and System**

- `networkmanager` → `net-misc/networkmanager`
- `firewalld` → `net-firewall/firewalld`
- `cpupower` → `sys-power/cpupower`

**Shell and Terminal**

- `zsh` → `app-shells/zsh`
- `oh-my-zsh` → GURU overlay `app-shells/ohmyzsh` (or install upstream via git)
- `zsh-autosuggestions` → `app-shells/zsh-autosuggestions`
- `zsh-syntax-highlighting` → `app-shells/zsh-syntax-highlighting`
- `fastfetch` → `app-misc/fastfetch`

**Applications**

- `firefox` → `www-client/firefox` or `www-client/firefox-bin`
- `thunderbird` → `mail-client/thunderbird` or `mail-client/thunderbird-bin`
- `kate` → `kde-apps/kate`
- `gimp` → `media-gfx/gimp`
- `mpv` → `media-video/mpv`
- `audacity` → `media-sound/audacity`
- `reaper` → overlay `media-sound/reaper` (often in GURU)
- `gwenview` → `kde-apps/gwenview`
- `spotify` → `media-sound/spotify` (exists in Gentoo, sometimes masked by license, overlays also provide it)
- `kdeconnect` → `kde-misc/kdeconnect`

**Gaming**

- `steam` → `games-util/steam-launcher` or `games-util/steam-meta` (steam overlay)
- `dxvk-bin` → `app-emulation/dxvk` or `app-emulation/dxvk-bin` (GURU)
- `lutris` → `games-util/lutris`
- `protonup-qt-bin` → `games-util/protonup-qt` (GURU)
- `cuda` → `dev-util/nvidia-cuda-toolkit`

**System Tools**

- `partitionmanager` → `kde-apps/partitionmanager`
- `ksystemlog` → `kde-apps/ksystemlog`
- `systemdgenie` → not needed, systemd tools are integrated
- `nohang` → `sys-apps/nohang` in an overlay (GURU)
- `mkinitcpio-firmware` → not needed on Gentoo, firmware handled by `sys-kernel/linux-firmware`
- `ark` → `kde-apps/ark`

---

## Troubleshooting and tips

- **No root found at boot** ensure the root partition type GUID is `8304` and the ESP is `EF00`, both on the same disk. Also ensure `bootctl` was installed on that ESP. You can always add `root=PARTUUID=<uuid>` to `/etc/kernel/cmdline` if needed, but the goal here is to keep it GUID‑driven.
- **NVIDIA on Wayland** you must have `nvidia_drm.modeset=1` on the kernel command line, and `gui-libs/egl-wayland` installed. KDE Plasma on Wayland should then pick GBM.
- **Binary packages missing** temporarily switch binrepo to baseline `x86-64` by editing `/etc/portage/binrepos.conf/gentoobinhost.conf`. Portage falls back to source automatically unless you used `--getbinpkgonly`.
- **Steam 32‑bit** make sure your profile is multilib. If you used a `nomultilib` profile by accident, switch to a multilib desktop profile and update world.
- **Firmware** keep `sys-kernel/linux-firmware` up to date. AMD microcode for CPUs is bundled there. The `gentoo-kernel-bin` will load early microcode when present in the initramfs.

---

## Appendix, Why this works without fstab

- The **Discoverable Partitions Specification** defines a set of partition type GUIDs for common mount points. The **systemd‑gpt‑auto‑generator** looks for these on the disk of the ESP at boot time and creates mount units dynamically. By giving root the x86‑64 root GUID and letting dracut use systemd in the initramfs, the root filesystem is found automatically, no `root=` kernel parameter and no `/etc/fstab` required.

---

## Quick command summary

```bash
# Partition
sgdisk --zap-all /dev/nvme0n1
sgdisk -o /dev/nvme0n1
sgdisk -n1:0:+1GiB -t1:EF00 -c1:EFI /dev/nvme0n1
sgdisk -n2:0:0     -t2:8304 -c2:root /dev/nvme0n1
mkfs.fat -F32 -n EFI  /dev/nvme0n1p1
mkfs.ext4 -L root     /dev/nvme0n1p2
mount /dev/nvme0n1p2 /mnt/gentoo && mkdir -p /mnt/gentoo/boot && mount /dev/nvme0n1p1 /mnt/gentoo/boot

# Stage3 (systemd) and chroot
cd /mnt/gentoo && wget -O stage3.tar.xz "$(wget -qO- https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt | awk '/xz/{print "https://distfiles.gentoo.org/releases/amd64/autobuilds/"$1; exit}')"
tar xpf stage3.tar.xz --xattrs-include='*' --numeric-owner
cp --dereference /etc/resolv.conf etc/
mount -t proc /proc proc; mount --rbind /sys sys; mount --make-rslave sys; mount --rbind /dev dev; mount --make-rslave dev
chroot /mnt/gentoo /bin/bash; source /etc/profile

# Portage and mirrors
emerge-webrsync && emaint sync -r gentoo
emerge --ask app-portage/gentoolkit app-portage/mirrorselect
mirrorselect -i -o >> /etc/portage/make.conf

# Binrepos and profile
mkdir -p /etc/portage/binrepos.conf
printf "[gentoo]\npriority = 90\nsync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/17.1/x86-64-v3/\n" > /etc/portage/binrepos.conf/gentoobinhost.conf
echo 'EMERGE_DEFAULT_OPTS="--getbinpkg --binpkg-respect-use=y --with-bdeps=y"' >> /etc/portage/make.conf
eselect profile list && eselect profile set <plasma+systemd profile number>

# USE, VIDEO_CARDS
cat >> /etc/portage/make.conf << 'EOF'
VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"
USE="egl wayland vulkan pipewire pulseaudio udev bluetooth dbus X kde plasma sddm qt5 qt6 opengl"
ABI_X86="64 32"
EOF

# Kernel, dracut, installkernel
emerge --ask sys-kernel/linux-firmware sys-kernel/gentoo-kernel-bin sys-kernel/dracut sys-kernel/installkernel
mkdir -p /etc/portage/package.use
printf 'sys-kernel/installkernel systemd systemd-boot dracut\n' > /etc/portage/package.use/installkernel
emerge --ask --newuse sys-kernel/installkernel

# Kernel cmdline and dracut NVIDIA
printf 'quiet loglevel=3 nvidia_drm.modeset=1 zswap.enabled=1 zswap.max_pool_percent=25\n' > /etc/kernel/cmdline
mkdir -p /etc/dracut.conf.d
printf 'add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "\n' > /etc/dracut.conf.d/10-nvidia.conf

# systemd-boot
bootctl --esp-path=/boot install
mkdir -p /boot/loader
printf 'default gentoo\ntimeout 3\neditor no\n' > /boot/loader/loader.conf

# Base system settings, user, sudo
ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime && hwclock --systohc
printf 'en_US.UTF-8 UTF-8\nnb_NO.UTF-8 UTF-8\n' > /etc/locale.gen && locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
echo 'mybox' > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 mybox\n' > /etc/hosts
emerge --ask app-admin/sudo && sed -i 's/^# %wheel/%wheel/' /etc/sudoers
passwd && useradd -m -G wheel,video,audio,plugdev,lp,storage -s /bin/zsh lars && passwd lars

# Networking and audio
emerge --ask net-misc/networkmanager net-firewall/firewalld sys-power/cpupower media-video/pipewire media-video/wireplumber
systemctl enable NetworkManager firewalld fstrim.timer
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service

# NVIDIA + KDE Plasma
emerge --ask x11-drivers/nvidia-drivers gui-libs/egl-wayland
emerge --ask kde-plasma/plasma-meta x11-misc/sddm kde-apps/dolphin kde-apps/konsole x11-terms/kitty
systemctl enable sddm

# Apps
emerge --ask www-client/firefox-bin mail-client/thunderbird-bin app-misc/fastfetch

# Exit and reboot
exit; umount -R /mnt/gentoo; reboot
```

---
