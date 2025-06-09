#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] at line $LINENO"; exit 1' ERR

# LFS Build Orchestrator — Version 1.0
# End-to-end automation for building a Linux From Scratch system

### Configuration ###
LFS=/mnt/lfs
LOG_DIR=/var/log/lfs-build
ISO_DIR=/iso
ISO_IMG=$PWD/lfs-live.iso
LFS_USER=lfs
LFS_PASSWORD='changeme'
MAKEFLAGS=-j$(nproc)
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=$LFS/tools/bin:$PATH

# Basic network configuration
HOSTNAME=lfs
NET_IFACE=eth0
IP_ADDR=192.168.1.2
GATEWAY=192.168.1.1
PREFIX=24
BROADCAST=192.168.1.255
DNS1=8.8.8.8
DNS2=8.8.4.4

# Filesystem partitions and types
ROOT_PART=/dev/sda2
SWAP_PART=/dev/sda5
ROOT_FS_TYPE=ext4

# Time zone and locale configuration
TIMEZONE=UTC
LOCALE="en_US.UTF-8"

# Root password (plain text)
ROOT_PASSWORD="root"

export LFS
umask 022

# Check for TUI toolkit
WHIPTAIL_BIN=$(command -v whiptail || true)

show_gauge() {
  local pct="$1" msg="$2" pid
  if [[ -n "$WHIPTAIL_BIN" ]]; then
    "$WHIPTAIL_BIN" --gauge "$msg" 6 60 "$pct" &
    pid=$!
  else
    printf "\r[%-50s] %3d%% - %s" "$(printf '#%.0s' $(seq 1 $((pct/2))))" "$pct" "$msg"
    pid=0
  fi
  echo "$pid"
}

run_with_progress() {
  local step=$1 total=$2 desc=$3 func=$4
  local pct=$(( step * 100 / total ))
  local start end dur pid
  pid=$(show_gauge "$pct" "$desc")
  start=$(date +%s)
  "$func"
  end=$(date +%s)
  dur=$(( end - start ))
  if [[ $pid -ne 0 ]]; then
    kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
  else
    echo
  fi
  printf '[INFO] %s completed in %ds\n' "$desc" "$dur"
}

check_lfs_env() {
  echo "[INFO] LFS: $LFS, umask: $(umask)"
  if [[ "$(umask)" != "0022" && "$(umask)" != "022" ]]; then
    echo "[ERROR] umask must be 022" >&2; exit 1
  fi
}

########################################
# Phases 4–7 omitted for brevity (as previously defined)
########################################

mount_virtual_fs() {
  mount -v --bind /dev "$LFS/dev"
  mount -v --bind /dev/pts "$LFS/dev/pts"
  mount -vt proc proc "$LFS/proc"
  mount -vt sysfs sysfs "$LFS/sys"
  mount -vt tmpfs tmpfs "$LFS/run"
  if [ -h "$LFS/dev/shm" ]; then
    install -dv -m1777 "$LFS$(realpath /dev/shm)"
  else
    mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
  fi
}

enter_chroot() {
  chroot "$LFS" /usr/bin/env -i \
    HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin LC_ALL=POSIX \
        HOSTNAME="$HOSTNAME" NET_IFACE="$NET_IFACE" IP_ADDR="$IP_ADDR" \
        GATEWAY="$GATEWAY" PREFIX="$PREFIX" BROADCAST="$BROADCAST" \
        DNS1="$DNS1" DNS2="$DNS2" \
        MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)" LFS_TGT="$LFS_TGT" \
    /bin/bash --login << 'EOF'
set -euo pipefail
export MAKEFLAGS TESTSUITEFLAGS LC_ALL LFS_TGT

# Chapters 7 completed above

# Chapter 8: Installing Basic System Software

# Define array of Chapter 8 packages
CH8_PACKAGES=(
  man-pages-6.12
  iana-etc-20250123
  glibc-2.41
  zlib-1.3.1
  bzip2-1.0.8
  xz-5.6.4
  lz4-1.10.0
  zstd-1.5.7
  file-5.46
  readline-8.2.13
  m4-1.4.19
  bc-7.0.3
  flex-2.6.4
  tcl-8.6.16
  expect-5.45.4
  dejagnu-1.6.3
  pkgconf-2.3.0
  binutils-2.44
  gmp-6.3.0
  mpfr-4.2.1
  mpc-1.3.1
  attr-2.5.2
  acl-2.3.2
  libcap-2.73
  libxcrypt-4.4.38
  shadow-4.17.3
  gcc-14.2.0
  ncurses-6.5
  sed-4.9
  psmisc-23.7
  gettext-0.24
  bison-3.8.2
  grep-3.11
  bash-5.2.37
  libtool-2.5.4
  gdbm-1.24
  gperf-3.1
  expat-2.6.4
  inetutils-2.6
  less-668
  perl-5.40.1
  xml-parser-2.47
  intltool-0.51.0
  autoconf-2.72
  automake-1.17
  openssl-3.4.1
  elfutils-0.192
  libffi-3.4.7
  python-3.13.2
  flit-core-3.11.0
  wheel-0.45.1
  setuptools-75.8.1
  ninja-1.12.1
  meson-1.7.0
  kmod-34
  coreutils-9.6
  check-0.15.2
  diffutils-3.11
  gawk-5.3.1
  findutils-4.10.0
  groff-1.23.0
  grub-2.12
  gzip-1.13
  iproute2-6.13.0
  kbd-2.7.1
  libpipeline-1.5.8
  make-4.4.1
  patch-2.7.6
  tar-1.35
  texinfo-7.2
  vim-9.1.1166
  markupsafe-3.0.2
  jinja2-3.1.5
  systemd-257.3
  systemd-man-pages-257.3
  man-db-2.13.0
  procps-ng-4.0.5
  util-linux-2.40.4
  e2fsprogs-1.47.2
  sysklogd-2.7.0
  sysvinit-3.14
)

for pkg in "${CH8_PACKAGES[@]}"; do
  echo ">>> Chapter 8: Building $pkg"
  cd /sources/$pkg
  case "$pkg" in
    man-pages-6.12)
      make prefix=/usr install ;;
    iana-etc-20250123)
      ./configure --prefix=/usr && make && make install ;;
    glibc-2.41)
      patch -Np1 -i ../glibc-2.41-fhs-1.patch
      mkdir -v build && cd build
      ../configure --prefix=/usr --host="$LFS_TGT" --build="$(../scripts/config.guess)" \
                   --enable-kernel=5.4 --with-headers=/usr/include \
                   --disable-nscd libc_cv_slibdir=/usr/lib
      make && make install ;;
    zlib-1.3.1)
      ./configure --prefix=/usr && make && make install ;;
    bzip2-1.0.8)
      patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
      make -f Makefile-libbz2_so && make clean
      make PREFIX=/usr install && cp -v libbz2.so.* /usr/lib && ln -sv libbz2.so.1.0 /usr/lib/libbz2.so ;;
    xz-5.6.4)
      ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xz-5.6.4
      make && make install ;;
    lz4-1.10.0)
      make PREFIX=/usr install ;;
    zstd-1.5.7)
      make PREFIX=/usr install ;;
    file-5.46)
      ./configure --prefix=/usr && make && make install ;;
    readline-8.2.13)
      ./configure --prefix=/usr --disable-static --with-curses
      make SHLIB_LIBS="-lncursesw" && make install ;;
    m4-1.4.19)
      ./configure --prefix=/usr && make && make install ;;
    bc-7.0.3)
      ./configure --prefix=/usr && make && make install ;;
    flex-2.6.4)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    tcl-8.6.16)
      cd unix && ./configure --prefix=/usr && make && make install ;;
    expect-5.45.4)
      ./configure --prefix=/usr --with-tcl=/usr/lib && make && make install ;;
    dejagnu-1.6.3)
      autoreconf -f -i && ./configure --prefix=/usr --enable-install-doc && make && make install ;;
    pkgconf-2.3.0)
      ./configure --prefix=/usr && make && make install ;;
    binutils-2.44)
      mkdir -v build && cd build
      ../configure --prefix=/usr --disable-nls --enable-shared --enable-64-bit-bfd \
                   --enable-new-dtags --enable-default-hash-style=gnu
      make && make install ;;
    gmp-6.3.0)
      ./configure --prefix=/usr --enable-cxx && make && make install ;;
    mpfr-4.2.1)
      ./configure --prefix=/usr --disable-static --enable-thread-safe && make && make install ;;
    mpc-1.3.1)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    attr-2.5.2|acl-2.3.2)
      ./configure --prefix=/usr && make && make install ;;
    libcap-2.73)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    libxcrypt-4.4.38)
      ./configure --prefix=/usr && make && make install ;;
    shadow-4.17.3)
      ./configure --prefix=/usr --sysconfdir=/etc && make && make install ;;
    gcc-14.2.0)
      mkdir -v build && cd build
      ../configure --prefix=/usr --disable-multilib --enable-languages=c,c++ \
                   --disable-bootstrap --disable-libsanitizer
      make && make install && ln -sv gcc /usr/bin/cc ;;
    ncurses-6.5)
      mkdir build && cd build && ../configure --prefix=/usr --mandir=/usr/share/man \
                   --with-shared --without-debug --without-normal --enable-pc-files \
                   --with-cxx-shared && make && make install && echo "" ;;
    sed-4.9)
      ./configure --prefix=/usr && make && make install ;;
    psmisc-23.7)
      ./configure --prefix=/usr && make && make install ;;
    gettext-0.24)
      ./configure --disable-shared && make && cp gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin ;;
    bison-3.8.2)
      ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2 && make && make install ;;
    grep-3.11)
      ./configure --prefix=/usr && make && make install ;;
    bash-5.2.37)
      ./configure --prefix=/usr --host="$LFS_TGT" --without-bash-malloc && make && make install && ln -sv bash /bin/sh ;;
    libtool-2.5.4)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    gdbm-1.24)
      ./configure --prefix=/usr && make && make install ;;
    gperf-3.1)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    expat-2.6.4)
      ./configure --prefix=/usr && make && make install ;;
    inetutils-2.6)
      ./configure --prefix=/usr --localstatedir=/var/mail && make && make install ;;
    less-668)
      ./configure --prefix=/usr && make && make install ;;
    perl-5.40.1)
      ./Configure -des -Dprefix=/usr -Dusrinc=/usr/include && make && make install ;;
    xml-parser-2.47)
      perl Makefile.PL PREFIX=/usr && make && make install ;;
    intltool-0.51.0)
      ./configure --prefix=/usr && make && make install ;;
    autoconf-2.72)
      ./configure --prefix=/usr && make && make install ;;
    automake-1.17)
      ./configure --prefix=/usr && make && make install ;;
    openssl-3.4.1)
      ./Configure --prefix=/usr --libdir=lib --openssldir=/etc/ssl && make && make install ;;
    elfutils-0.192)
      mkdir -v build && cd build && ../configure --prefix=/usr --disable-debuginfod && make && make install ;;
    libffi-3.4.7)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    python-3.13.2)
      ./configure --prefix=/usr --enable-shared --without-ensurepip && make && make install ;;
    flit-core-3.11.0|wheel-0.45.1|setuptools-75.8.1)
      python3 -m pip install --prefix=/usr $pkg ;;
    ninja-1.12.1)
      ./configure --bootstrap && cp ninja /usr/bin ;;
    meson-1.7.0)
      python3 setup.py build && python3 setup.py install ;;
    kmod-34)
      ./configure --prefix=/usr && make && make install ;;
    coreutils-9.6)
      ./configure --prefix=/usr --host="$LFS_TGT" --build="$(build-aux/config.guess)" && make && make install ;;
    check-0.15.2)
      ./configure --prefix=/usr && make && make install ;;
    diffutils-3.11)
      ./configure --prefix=/usr && make && make install ;;
    gawk-5.3.1)
      ./configure --prefix=/usr && make && make install ;;
    findutils-4.10.0)
      ./configure --prefix=/usr --localstatedir=/var/lib/locate && make && make install ;;
    groff-1.23.0)
      ./configure --prefix=/usr --sysconfdir=/etc groff_cv_forced_unlink=true && make && make install ;;
    grub-2.12)
      ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu && make && make install ;;
    gzip-1.13)
      ./configure --prefix=/usr && make && make install ;;
    iproute2-6.13.0)
      ./configure --prefix=/usr && make && make install ;;
    kbd-2.7.1)
      ./configure --prefix=/usr --with-models="etc/vconsole" && make && make install ;;
    libpipeline-1.5.8)
      ./configure --prefix=/usr && make && make install ;;
    make-4.4.1)
      ./configure --prefix=/usr --without-guile && make && make install ;;
    patch-2.7.6)
      ./configure --prefix=/usr && make && make install ;;
    tar-1.35)
      ./configure --prefix=/usr && make && make install ;;
    texinfo-7.2)
      ./configure --prefix=/usr && make && make install ;;
    vim-9.1.1166)
      ./configure --prefix=/usr --with-features=huge --enable-multibyte && make && make install ;;
    markupsafe-3.0.2)
      python3 -m pip install --prefix=/usr MarkupSafe ;;
    jinja2-3.1.5)
      python3 -m pip install --prefix=/usr Jinja2 ;;
    systemd-257.3)
      ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var && make && make install ;;
    systemd-man-pages-257.3)
      ./configure --prefix=/usr && make && make install ;;
    man-db-2.13.0)
      ./configure --prefix=/usr --sysconfdir=/etc && make && make install ;;
    procps-ng-4.0.5)
      ./configure --prefix=/usr --disable-static && make && make install ;;
    util-linux-2.40.4)
      mkdir -pv /var/lib/hwclock && \
      ./configure --prefix=/usr --libdir=/usr/lib --runstatedir=/run \
                   --disable-chfn-chsh --disable-login --disable-nologin \
                   --disable-su --disable-setpriv --disable-runuser \
                   --disable-pylibmount --disable-static \
                   --disable-liblastlog2 --without-python \
                   ADJTIME_PATH=/var/lib/hwclock/adjtime \
                   --docdir=/usr/share/doc/util-linux-2.40.4 \
      && make && make install ;;
    e2fsprogs-1.47.2)
      ./configure --prefix=/usr --enable-elf-shlibs && make && make install ;;
    sysklogd-2.7.0)
      ./configure --prefix=/usr && make && make install ;;
  sysvinit-3.14)
      ./configure --prefix=/usr && make && make install ;;
  esac
done

# Install LFS Bootscripts (Chapter 9)
cd /sources/LFS-Bootscripts-20240825
make install

# Final system configuration
  ln -sv /proc/self/mounts /etc/mtab

  echo "$HOSTNAME" > /etc/hostname

  cat > /etc/hosts << EOF
  127.0.0.1  localhost.localdomain localhost
  127.0.1.1  ${HOSTNAME}.localdomain $HOSTNAME
  $IP_ADDR   ${HOSTNAME}.localdomain $HOSTNAME
  ::1        localhost ip6-localhost ip6-loopback
  ff02::1    ip6-allnodes
  ff02::2    ip6-allrouters
EOF

  cat > /etc/resolv.conf << EOF
  # Begin /etc/resolv.conf
  nameserver $DNS1
  nameserver $DNS2
  # End /etc/resolv.conf
EOF

  mkdir -p /etc/sysconfig
  cat > /etc/sysconfig/ifconfig.$NET_IFACE << EOF
  ONBOOT=yes
  IFACE=$NET_IFACE
  SERVICE=ipv4-static
  IP=$IP_ADDR
  GATEWAY=$GATEWAY
  PREFIX=$PREFIX
  BROADCAST=$BROADCAST
EOF

  cat > /etc/sysconfig/clock << "EOF"
  # Begin /etc/sysconfig/clock
  UTC=1
  CLOCKPARAMS=
  # End /etc/sysconfig/clock
EOF

  cat > /etc/sysconfig/console << "EOF"
  # Begin /etc/sysconfig/console
  UNICODE="1"
  FONT="Lat2-Terminus16"
  # End /etc/sysconfig/console
EOF

  cat > /etc/inittab << "EOF"
  # Begin /etc/inittab

  id:3:initdefault:

  si::sysinit:/etc/rc.d/init.d/rc S

  l0:0:wait:/etc/rc.d/init.d/rc 0
  l1:S1:wait:/etc/rc.d/init.d/rc 1
  l2:2:wait:/etc/rc.d/init.d/rc 2
  l3:3:wait:/etc/rc.d/init.d/rc 3
  l4:4:wait:/etc/rc.d/init.d/rc 4
  l5:5:wait:/etc/rc.d/init.d/rc 5
  l6:6:wait:/etc/rc.d/init.d/rc 6

  ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now

  su:S06:once:/sbin/sulogin
  s1:1:respawn:/sbin/sulogin

  1:2345:respawn:/sbin/agetty --noclear tty1 9600
  2:2345:respawn:/sbin/agetty tty2 9600
  3:2345:respawn:/sbin/agetty tty3 9600
  4:2345:respawn:/sbin/agetty tty4 9600
  5:2345:respawn:/sbin/agetty tty5 9600
  6:2345:respawn:/sbin/agetty tty6 9600

  # End /etc/inittab
EOF

  cat > /etc/sysconfig/rc.site << EOF
  # rc.site
  HOSTNAME=$HOSTNAME
EOF

  ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

  ### Section 10: Making the LFS Bootable ###
  cat > /etc/fstab << "EOF"
  
  # Begin /etc/fstab

  # file system  mount-point    type     options             dump  fsck order
  $ROOT_PART     /              $ROOT_FS_TYPE    defaults            1     1
  $SWAP_PART     swap           swap     pri=1               0     0
  proc           /proc          proc     nosuid,noexec,nodev 0     0
  sysfs          /sys           sysfs    nosuid,noexec,nodev 0     0
  devpts         /dev/pts       devpts   gid=5,mode=620      0     0
  tmpfs          /run           tmpfs    defaults            0     0
  devtmpfs       /dev           devtmpfs mode=0755,nosuid    0     0
  tmpfs          /dev/shm       tmpfs    nosuid,nodev        0     0
  cgroup2        /sys/fs/cgroup cgroup2  nosuid,noexec,nodev 0     0

  # End /etc/fstab
EOF

  cat > /etc/profile << EOF
  # Begin /etc/profile

  for i in \$(locale); do
    unset \${i%=*}
  done

  if [[ "\$TERM" = linux ]]; then
    export LANG=C.UTF-8
  else
    export LANG=$LOCALE
  fi

  # End /etc/profile
EOF

  cat > /etc/inputrc << "EOF"
  # Begin /etc/inputrc
  set horizontal-scroll-mode Off
  set meta-flag On
  set input-meta On
  set convert-meta Off
  set output-meta On
  set bell-style none
  "\eOd": backward-word
  "\eOc": forward-word
  "\e[1~": beginning-of-line
  "\e[4~": end-of-line
  "\e[5~": beginning-of-history
  "\e[6~": end-of-history
  "\e[3~": delete-char
  "\e[2~": quoted-insert
  "\eOH": beginning-of-line
  "\eOF": end-of-line
  "\e[H": beginning-of-line
  "\e[F": end-of-line
  # End /etc/inputrc
EOF

  cat > /etc/shells << "EOF"
  # Begin /etc/shells
  /bin/sh
  /bin/bash
  # End /etc/shells
EOF

  echo "root:$ROOT_PASSWORD" | chpasswd
# Create passwd and group as per LFS Book
cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/run/uuid:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
# Create tester user
echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester
# Initialize log files
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp utmp /var/log/lastlog
chmod 664 /var/log/lastlog
chmod 600 /var/log/btmp

# About Debugging Symbols
# Strip debugging symbols to reduce footprint (preserve separately if needed)
find /usr/{lib,libexec} -type f -name '*.so*' -exec strip --strip-debug '{}' + || true

# Stripping
# Remove unneeded symbols from binaries
strip --strip-unneeded /usr/bin/* /usr/sbin/* /bin/* /sbin/* || true

# Cleaning Up
# Remove libtool archives and documentation
find /usr/{lib,libexec} -name '*.la' -delete
rm -rf /usr/share/{info,man,doc}/*

### Section 10.3: Building the Linux Kernel ###
# Build and install the Linux kernel
cd /sources/linux-6.13.4
make mrproper
make defconfig
make -j"${MAKEFLAGS#-j}"
make modules_install
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.13.4-lfs-12.3
cp -iv System.map /boot/System.map-6.13.4
cp -iv .config /boot/config-6.13.4
cp -r Documentation -T /usr/share/doc/linux-6.13.4
chown -R 0:0 .

# Configure module load order
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "EOF"
# Begin /etc/modprobe.d/usb.conf

install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true

# End /etc/modprobe.d/usb.conf
EOF

### Section 10.4: Using GRUB to Set Up the Boot Process ###
# Install and configure GRUB
grub-install /dev/sda
cat > /boot/grub/grub.cfg << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_gpt
insmod ext2
set root=(hd0,2)
set gfxpayload=1024x768x32

menuentry "GNU/Linux, Linux 6.13.4-lfs-12.3" {
        linux   /boot/vmlinuz-6.13.4-lfs-12.3 root=/dev/sda2 ro
}
# End /boot/grub/grub.cfg
EOF

exit
EOF
}

main() {
  local steps=(check_lfs_env mount_virtual_fs enter_chroot)
  local total=${#steps[@]}
  local i=0
  for func in "${steps[@]}"; do
    i=$((i + 1))
    run_with_progress "$i" "$total" "$func" "$func"
  done
}

main "$@"
