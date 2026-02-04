#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[ERROR] at line $LINENO"; exit 1' ERR

# BLFS Build Automation Script - Version 2.2
# This script installs Beyond Linux From Scratch packages. For the
# first few packages of Chapter 4 (Security) the build steps are
# written out explicitly using the BLFS stable book instructions.
# Remaining packages are fetched dynamically from the BLFS website
# (https://www.linuxfromscratch.org/blfs/view/stable/).

### Configuration ###
# Root of the existing LFS system
BLFS=/mnt/lfs
LOG_DIR=/var/log/blfs-build
MAKEFLAGS=-j$(nproc)
BLFS_BASE=https://www.linuxfromscratch.org/blfs/view/stable

export BLFS MAKEFLAGS

# X Window System build environment (Chapter 24)
export XORG_PREFIX=/usr
export XORG_CONFIG="--prefix=$XORG_PREFIX --sysconfdir=/etc \
    --localstatedir=/var --disable-static"

umask 022

mkdir -p "$LOG_DIR"

# Show usage information
usage() {
  cat <<EOF
Usage: $0 [--chapters LIST]
Run BLFS instructions from the stable book.

  --chapters LIST  Comma-separated chapter numbers (e.g. 5,6).
                   When omitted, all chapters 4-50 are processed.
  -h, --help       Show this help and exit.
EOF
}

# Parse command line arguments
CHAPTERS=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--chapters)
      CHAPTERS=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Generic helper for running commands and logging output
run_step() {
  local name="$1"; shift
  echo "[BLFS] Starting $name" | tee -a "$LOG_DIR/${name}.log"
  { "$@"; } >> "$LOG_DIR/${name}.log" 2>&1
  echo "[BLFS] Completed $name" | tee -a "$LOG_DIR/${name}.log"
}

# Automatically download and execute build commands from BLFS

prepare_index() {
  INDEX_FILE=/tmp/blfs_index.html
  if [ ! -f "$INDEX_FILE" ]; then
    curl -fsL "$BLFS_BASE/" -o "$INDEX_FILE"
  fi
}

get_package_list() {
  prepare_index
  python3 - "$INDEX_FILE" "$CHAPTERS" <<'EOF'
import sys, bs4, re
html=open(sys.argv[1]).read()
chap_filter=set()
if len(sys.argv) > 2 and sys.argv[2]:
    chap_filter={int(c) for c in sys.argv[2].split(',') if c}
soup=bs4.BeautifulSoup(html, 'html.parser')
for ch in soup.find_all('li', class_='chapter'):
    h4=ch.find('h4')
    if not h4:
        continue
    m=re.match(r'(\d+)\. ', h4.get_text(strip=True))
    if not m:
        continue
    num=int(m.group(1))
    if 4 <= num <= 50 and (not chap_filter or num in chap_filter):
        for li in ch.find_all('li', class_='sect1'):
            a=li.find('a')
            if a:
                print(f"{a.get_text(strip=True)}|{a['href']}")
EOF
}

fetch_commands() {
  local path="$1"
  curl -fsL "$BLFS_BASE/$path" | \
    hxnormalize -x | hxselect -s '\n' -c 'pre' | hxunent | sed 's/<[^>]*>//g'
}

run_package() {
  local name="$1" path="$2"
  local cmds
  cmds=$(fetch_commands "$path")
  run_step "$name" bash -c "$cmds"
}

# Chapter 4: Security

build_make_ca() {
  run_step "make-ca" bash -e <<'EOF'
make install
install -vdm755 /etc/ssl/local
/usr/sbin/make-ca -g
EOF
}

build_cracklib() {
  run_step "CrackLib" bash -e <<'EOF'
CPPFLAGS+=' -I /usr/include/python3.13' \
./configure --prefix=/usr \
    --disable-static \
    --with-default-dict=/usr/lib/cracklib/pw_dict
make
make install
xzcat ../cracklib-words-2.10.3.xz > /usr/share/dict/cracklib-words
ln -v -sf cracklib-words /usr/share/dict/words
echo $(hostname) >> /usr/share/dict/cracklib-extra-words
install -v -m755 -d /usr/lib/cracklib
create-cracklib-dict /usr/share/dict/cracklib-words /usr/share/dict/cracklib-extra-words
EOF
}

build_cryptsetup() {
  run_step "cryptsetup" bash -e <<'EOF'
./configure --prefix=/usr \
    --disable-ssh-token \
    --disable-asciidoc
make
make install
EOF
}

build_cyrus_sasl() {
  run_step "cyrus-sasl" bash -e <<'EOF'
sed '/saslint/a #include <time.h>'       -i lib/saslutil.c
sed '/plugin_common/a #include <time.h>' -i plugins/cram.c
./configure --prefix=/usr \
    --sysconfdir=/etc \
    --enable-auth-sasldb \
    --with-dblib=lmdb \
    --with-dbpath=/var/lib/sasl/sasldb2 \
    --with-sphinx-build=no \
    --with-saslauthd=/var/run/saslauthd
make -j1
make install
install -v -dm755                          /usr/share/doc/cyrus-sasl-2.1.28/html
install -v -m644  saslauthd/LDAP_SASLAUTHD /usr/share/doc/cyrus-sasl-2.1.28
install -v -m644  doc/legacy/*.html        /usr/share/doc/cyrus-sasl-2.1.28/html
install -v -dm700 /var/lib/sasl
EOF
}

build_gnupg() {
  run_step "gnupg" bash -e <<'CMD'
mkdir build
cd build
../configure --prefix=/usr \
             --localstatedir=/var \
             --sysconfdir=/etc \
             --docdir=/usr/share/doc/gnupg-2.4.7
make
makeinfo --html --no-split -I doc -o doc/gnupg_nochunks.html ../doc/gnupg.texi
makeinfo --plaintext       -I doc -o doc/gnupg.txt           ../doc/gnupg.texi
make -C doc html
make -C doc pdf
make install
install -v -m755 -d /usr/share/doc/gnupg-2.4.7/html
install -v -m644 doc/gnupg_nochunks.html \
               /usr/share/doc/gnupg-2.4.7/html/gnupg.html
install -v -m644 ../doc/*.texi doc/gnupg.txt \
               /usr/share/doc/gnupg-2.4.7
install -v -m644 doc/gnupg.html/* \
               /usr/share/doc/gnupg-2.4.7/html
install -v -m644 doc/gnupg.pdf /usr/share/doc/gnupg-2.4.7
CMD
}

build_gnutls() {
  run_step "gnutls" bash -e <<'CMD'
./configure --prefix=/usr \
            --docdir=/usr/share/doc/gnutls-3.8.9 \
            --with-default-trust-store-pkcs11="pkcs11:"
make
make install
CMD
}

build_iptables() {
  run_step "iptables" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-nftables \
            --enable-libipq
make
make install
CMD
}

build_openssh() {
  run_step "openssh" bash -e <<'CMD'
install -v -g sys -m700 -d /var/lib/sshd
groupadd -g 50 sshd 2>/dev/null || true
useradd  -c 'sshd PrivSep' \
         -d /var/lib/sshd  \
         -g sshd           \
         -s /bin/false     \
         -u 50 sshd 2>/dev/null || true
./configure --prefix=/usr \
            --sysconfdir=/etc/ssh \
            --with-privsep-path=/var/lib/sshd \
            --with-default-path=/usr/bin \
            --with-superuser-path=/usr/sbin:/usr/bin \
            --with-pid-dir=/run
make
make install
install -v -m755 contrib/ssh-copy-id /usr/bin
install -v -m644 contrib/ssh-copy-id.1 /usr/share/man/man1
install -v -m755 -d /usr/share/doc/openssh-9.9p2
install -v -m644 INSTALL LICENCE OVERVIEW README* \
               /usr/share/doc/openssh-9.9p2
CMD
}

build_gpgme() {
  run_step "gpgme" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-gpg-test
make
make install
CMD
}

build_gpgmepp() {
  run_step "gpgmepp" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D GPGME_INCLUDE_DIR=/usr/include/gpgme \
      -G Ninja ..
ninja
ninja install
CMD
}

build_libcap_pam() {
  run_step "libcap-pam" bash -e <<'CMD'
make -C pam_cap
install -v -m755 pam_cap/pam_cap.so /usr/lib/security
install -v -m644 pam_cap/capability.conf /etc/security
CMD
}

build_linux_pam() {
  run_step "Linux-PAM" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D docdir=/usr/share/doc/Linux-PAM-1.7.0 ..
ninja
ninja install
chmod -v 4755 /usr/sbin/unix_chkpwd

install -vdm755 /etc/pam.d

cat > /etc/pam.d/system-account << "EOF"
account   required    pam_unix.so
EOF

cat > /etc/pam.d/system-auth << "EOF"
auth      required    pam_unix.so
EOF

cat > /etc/pam.d/system-session << "EOF"
session   required    pam_unix.so
EOF

cat > /etc/pam.d/system-password << "EOF"
password  required    pam_unix.so       sha512 shadow try_first_pass
EOF

cat > /etc/pam.d/other << "EOF"
auth        required        pam_warn.so
auth        required        pam_deny.so
account     required        pam_warn.so
account     required        pam_deny.so
password    required        pam_warn.so
password    required        pam_deny.so
session     required        pam_warn.so
session     required        pam_deny.so
EOF
CMD
}

build_libpwquality() {
  run_step "libpwquality" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --with-securedir=/usr/lib/security \
            --with-python-binary=python3
make
make install
CMD
}

build_mitkrb() {
  run_step "MIT-Kerberos" bash -e <<'CMD'
cd src
sed -e '/eq 0/{N;s/12 //}'   \
    -e 's/yacc/bison -y/' \
    -i configure
./configure --prefix=/usr            \
            --sysconfdir=/etc        \
            --localstatedir=/var/lib \
            --runstatedir=/run       \
            --with-system-et         \
            --with-system-ss         \
            --with-system-verto=no   \
            --enable-dns-for-realm
make
make install

install -v -dm755 /usr/share/doc/krb5-1.21.3
cp -vfr ../doc/*  /usr/share/doc/krb5-1.21.3
CMD
}

build_nettle() {
  run_step "nettle" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
chmod -v 755 /usr/lib/lib{hogweed,nettle}.so
CMD
}

build_nss() {
  run_step "nss" bash -e <<'CMD'
make BUILD_OPT=1                      \
  NSPR_INCLUDE_DIR=/usr/include/nspr  \
  USE_SYSTEM_ZLIB=1                   \
  ZLIB_LIBS=-lz                       \
  NSS_USE_SYSTEM_SQLITE=1             \
  NSS_DISABLE_GTESTS=1                \
  $([ "$(uname -m)" = x86_64 ] && echo USE_64=1)

install -v -m755 -d /usr/lib/pkgconfig
install -v -m755 dist/Linux*/lib/*.so        /usr/lib
install -v -m644 dist/Linux*/lib/*.chk       /usr/lib
install -v -m644 dist/Linux*/lib/libcrmf.a   /usr/lib
install -v -m755 -d /usr/include/nss
install -v -m644 dist/public/nss/*           /usr/include/nss

cat > /usr/lib/pkgconfig/nss.pc << "EOF"
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include/nss

Name: NSS
Description: Network Security Services
Version: 3.107
Requires: nspr >= 4.36
Cflags: -I${includedir}
Libs: -L${libdir} -lnss3 -lnssutil3 -lsmime3 -lssl3 -lsoftokn3
EOF

ln -sfv libsoftokn3.so /usr/lib/libsoftokn3.chk
ln -sfv libfreeblpriv3.so /usr/lib/libfreeblpriv3.chk
CMD
}

build_p11_kit() {
  run_step "p11-kit" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D trust_paths=/etc/pki/anchors ..
ninja
ninja install
ln -sfv /usr/libexec/p11-kit/trust-module-p11-kit-proxy /usr/lib/pkcs11/
CMD
}

build_polkit() {
  run_step "polkit" bash -e <<'CMD'
groupadd -fg 27 polkitd
useradd -c "PolicyKit Daemon Owner" -d /etc/polkit-1 -u 27 \
        -g polkitd -s /bin/false polkitd 2>/dev/null || true

mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D man=true             \
            -D session_tracking=elogind \
            -D tests=false ..
ninja
ninja install
CMD
}

build_polkit_gnome() {
  run_step "polkit-gnome" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_shadow() {
  run_step "shadow" bash -e <<'CMD'
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i \
  's/groups\.1 / /'   \
  's/getspnam\.3 / /' \
  's/passwd\.5 / /'   {} \;

sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs

./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --with-group-name-max-length=32
make
make exec_prefix=/usr install
make -C man install-man

install -v -m644 /dev/null /etc/default/useradd

cat > /etc/pam.d/login << "EOF"
auth      optional    pam_faildelay.so  delay=3000000
auth      requisite   pam_nologin.so
auth      include     system-auth
account   required    pam_access.so
account   include     system-account
session   required    pam_env.so
session   required    pam_limits.so
session   required    pam_lastlog.so
session   include     system-session
password  include     system-password
EOF

cat > /etc/pam.d/passwd << "EOF"
password  include     system-password
EOF

cat > /etc/pam.d/su << "EOF"
auth      sufficient  pam_rootok.so
auth      include     system-auth
auth      required    pam_wheel.so use_uid
account   include     system-account
session   required    pam_env.so
session   include     system-session
EOF

cat > /etc/pam.d/chpasswd << "EOF"
auth      sufficient  pam_rootok.so
password  include     system-password
EOF

for PROGRAM in chfn chgpasswd chsh groupadd groupdel \
               groupmems groupmod newusers useradd userdel usermod; do
  install -v -m644 /etc/pam.d/chpasswd /etc/pam.d/${PROGRAM}
  sed -i "s/chpasswd/${PROGRAM}/" /etc/pam.d/${PROGRAM}
done
CMD
}

build_ssh_askpass() {
  run_step "ssh-askpass" bash -e <<'CMD'
cd contrib
make gnome-ssh-askpass3
install -v -m755 gnome-ssh-askpass3 /usr/libexec/openssh/ssh-askpass
ln -sfv /usr/libexec/openssh/ssh-askpass /usr/bin/ssh-askpass
CMD
}

build_stunnel() {
  run_step "stunnel" bash -e <<'CMD'
groupadd -g 51 stunnel 2>/dev/null || true
useradd -c "stunnel Daemon" -d /var/lib/stunnel \
        -g stunnel -s /bin/false -u 51 stunnel 2>/dev/null || true

./configure --prefix=/usr        \
            --sysconfdir=/etc    \
            --localstatedir=/var \
            --disable-fips-mode
make
make install
CMD
}

build_sudo() {
  run_step "sudo" bash -e <<'CMD'
./configure --prefix=/usr              \
            --libexecdir=/usr/lib      \
            --with-secure-path         \
            --with-env-editor          \
            --docdir=/usr/share/doc/sudo-1.9.16p2 \
            --with-passprompt="[sudo] password for %p: " \
            --with-all-insults
make
make install
ln -sfv libsudo_util.so.0.0.0 /usr/lib/sudo/libsudo_util.so.0

cat > /etc/pam.d/sudo << "EOF"
auth      include     system-auth
account   include     system-account
password  include     system-password
session   include     system-session
EOF
CMD
}

build_tripwire() {
  run_step "tripwire" bash -e <<'CMD'
sed -e 's|TWDB="${prefix}|TWDB="/var|'    \
    -e '/TWMAN/ s|${prefix}|/usr/share|'  \
    -e '/TWDOCS/ s|${prefix}|/usr/share|' \
    -i installer/install.cfg

autoreconf -fi
CPPFLAGS=-std=c++11 \
./configure --prefix=/usr \
            --sysconfdir=/etc/tripwire
make
make install
CMD
}

build_liboauth() {
  run_step "liboauth" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static
make
make install
CMD
}

main() {
  local packages
  packages=$(get_package_list)
  while IFS='|' read -r name path; do
    case $name in
      make-ca-*)        build_make_ca ;;
      CrackLib-*)       build_cracklib ;;
      cryptsetup-*)     build_cryptsetup ;;
      "Cyrus SASL"*)   build_cyrus_sasl ;;
      GnuPG-*)         build_gnupg ;;
      GnuTLS-*)        build_gnutls ;;
      iptables-*)      build_iptables ;;
      OpenSSH-*)       build_openssh ;;
      gpgme-*)          build_gpgme ;;
      gpgmepp-*)        build_gpgmepp ;;
      libcap-*)         build_libcap_pam ;;
      Linux-PAM-*)      build_linux_pam ;;
      libpwquality-*)   build_libpwquality ;;
      "MIT Kerberos"*)  build_mitkrb ;;
      Nettle-*)         build_nettle ;;
      NSS-*)            build_nss ;;
      p11-kit-*)        build_p11_kit ;;
      Polkit-*)         build_polkit ;;
      polkit-gnome-*)   build_polkit_gnome ;;
      Shadow-*)         build_shadow ;;
      ssh-askpass-*)    build_ssh_askpass ;;
      stunnel-*)        build_stunnel ;;
      Sudo-*)           build_sudo ;;
      Tripwire-*)       build_tripwire ;;
      liboauth-*)       build_liboauth ;;
      btrfs-progs-*)    build_btrfs_progs ;;
      dosfstools-*)     build_dosfstools ;;
      Fuse-*)           build_fuse ;;
      jfsutils-*)       build_jfsutils ;;
      LVM2-*)           build_lvm2 ;;
      mdadm-*)          build_mdadm ;;
      ntfs-3g-*)        build_ntfs_3g ;;
      gptfdisk-*)       build_gptfdisk ;;
      parted-*)         build_parted ;;
      smartmontools-*)  build_smartmontools ;;
      sshfs-*)          build_sshfs ;;
      xfsprogs-*)       build_xfsprogs ;;
      efivar-*)         build_efivar ;;
      efibootmgr-*)     build_efibootmgr ;;
      "GRUB-"*)        build_grub_efi ;;
      Bluefish-*)       build_bluefish ;;
      Ed-*)             build_ed ;;
      Emacs-*)          build_emacs ;;
      Gedit-*)          build_gedit ;;
      JOE-*)            build_joe ;;
      kate-*)           build_kate ;;
      Mousepad-*)       build_mousepad ;;
      Nano-*)           build_nano ;;
      Vim-*)            build_vim ;;
      qemu-*)           build_qemu ;;
      Abseil-cpp-*)     build_abseil_cpp ;;
      AppStream-*)      build_appstream ;;
      appstream-glib-*) build_appstream_glib ;;
      Apr-*)            build_apr ;;
      Apr-Util-*)       build_apr_util ;;
      boost-*)          build_boost ;;
      brotli-*)         build_brotli ;;
      libarchive-*)     build_libarchive ;;
      libassuan-*)      build_libassuan ;;
      libgpg-error-*)   build_libgpg_error ;;
      libgcrypt-*)      build_libgcrypt ;;
      libxml2-*)        build_libxml2 ;;
      Aspell-*)         build_aspell ;;
      CLucene-*)        build_clucene ;;
      dbus-glib-*)      build_dbus_glib ;;
      double-conversion-*) build_double_conversion ;;
      duktape-*)        build_duktape ;;
      enchant-*)        build_enchant ;;
      Exempi-*)         build_exempi ;;
      fftw-*)           build_fftw ;;
      fmt-*)            build_fmt ;;
      GLib-[0-9]*|glib2-*) build_glib ;;
      glibmm-[0-9]*|glibmm2-*) build_glibmm ;;
      GMime-*)          build_gmime ;;
      gspell-*)         build_gspell ;;
      highway-*)        build_highway ;;
      icu-*)            build_icu ;;
      JSON-C-*)         build_json_c ;;
      keyutils-*)       build_keyutils ;;
      libaio-*)         build_libaio ;;
      libatasmart-*)    build_libatasmart ;;
      libdaemon-*)      build_libdaemon ;;
      Node.js-*)        build_nodejs ;;
      NSPR-*)           build_nspr ;;
      Protobuf-*)       build_protobuf ;;
      qcoro-*)          build_qcoro ;;
      Talloc-*)         build_talloc ;;
      Uchardet-*)       build_uchardet ;;
      Wayland-[0-9]*|wayland-*) build_wayland ;;
      Wayland-Protocols-*) build_wayland_protocols ;;
      wv-*)             build_wv ;;
      Xapian-*)         build_xapian ;;
      PCRE2-*)          build_pcre2 ;;
      fast_float-*)     build_fast_float ;;
      libproxy-*)       build_libproxy ;;
      AAlib-*)          build_aalib ;;
      FreeType-*)       build_freetype ;;
      Fontconfig-*)     build_fontconfig ;;
      harfbuzz-*)       build_harfbuzz ;;
      libpng-*)         build_libpng ;;
      libtiff-*)        build_libtiff ;;
      babl-*)           build_babl ;;
      Exiv2-*)          build_exiv2 ;;
      FriBidi-*)        build_fribidi ;;
      gegl-*)           build_gegl ;;
      giflib-*)         build_giflib ;;
      Glad-*)           build_glad ;;
      GLM-*)            build_glm ;;
      Graphite2-*)      build_graphite2 ;;
      jasper-*)         build_jasper ;;
      "Little CMS"*)    build_lcms2 ;;
      libavif-*)        build_libavif ;;
      libexif-*)        build_libexif ;;
      libgxps-*)        build_libgxps ;;
      libjpeg-turbo-*)  build_libjpeg_turbo ;;
      libjxl-*)         build_libjxl ;;
      libmng-*)         build_libmng ;;
      libmypaint-*)     build_libmypaint ;;
      libraw-*)         build_libraw ;;
      librsvg-*)        build_librsvg ;;
      Libspiro-*)       build_libspiro ;;
      libwebp-*)        build_libwebp ;;
      mypaint-brushes-*) build_mypaint_brushes ;;
      newt-*)           build_newt ;;
      opencv-*)         build_opencv ;;
      OpenJPEG-*)       build_openjpeg ;;
      Pixman-*)         build_pixman ;;
      Poppler-*)        build_poppler ;;
      Potrace-*)        build_potrace ;;
      Qpdf-*)           build_qpdf ;;
      qrencode-*)       build_qrencode ;;
      sassc-*)          build_sassc ;;
      webp-pixbuf-loader-*) build_webp_pixbuf_loader ;;
      woff2-*)          build_woff2 ;;
      zxing-cpp-*)      build_zxing_cpp ;;
      gmmlib-*)         build_gmmlib ;;&
      gsl-*)            build_gsl ;;&
      inih-*)           build_inih ;;&
      Jansson-*)        build_jansson ;;&
      JSON-GLib-*)      build_json_glib ;;&
      libatomic_ops-*)  build_libatomic_ops ;;&
      libblockdev-*)    build_libblockdev ;;&
      libbytesize-*)    build_libbytesize ;;&
      libclc-*)         build_libclc ;;&
      libcloudproviders-*) build_libcloudproviders ;;&
      libdisplay-info-*) build_libdisplay_info ;;&
      libgsf-*)         build_libgsf ;;&
      libgudev-*)       build_libgudev ;;&
      libgusb-*)        build_libgusb ;;&
      libical-*)        build_libical ;;
      libidn-*)        build_libidn ;;
      libidn2-*)       build_libidn2 ;;
      libksba-*)      build_libksba ;;
      liblinear-*)    build_liblinear ;;
      libmbim-*)      build_libmbim ;;
      libnvme-*)      build_libnvme ;;
      libpaper-*)     build_libpaper ;;
      libportal-*)    build_libportal ;;
      libptytty-*)    build_libptytty ;;
      libqalculate-*) build_libqalculate ;;
      libqmi-*)       build_libqmi ;;
      libseccomp-*)   build_libseccomp ;;
      libsigc++-2.*)  build_libsigc2 ;;
      libsigc++-3.*)  build_libsigc3 ;;
      libsigsegv-*)   build_libsigsegv ;;
      libssh2-*)      build_libssh2 ;;
      libstatgrab-*)  build_libstatgrab ;;
      libtasn1-*)     build_libtasn1 ;;
      libunistring-*) build_libunistring ;;
      libunwind-*)    build_libunwind ;;
      liburcu-*)      build_liburcu ;;
      libusb-*)       build_libusb ;;
      libuv-*)        build_libuv ;;
      libxkbcommon-*) build_libxkbcommon ;;
      libxmlb-*)      build_libxmlb ;;
      libxslt-*)      build_libxslt ;;
      libwacom-*)     build_libwacom ;;
      libyaml-*)      build_libyaml ;;
      log4cplus-*)    build_log4cplus ;;
      LZO-*)          build_lzo ;;
      mtdev-*)        build_mtdev ;;
      npth-*)         build_npth ;;
      Popt-*)         build_popt ;;
      Protobuf-c-*)   build_protobuf_c ;;
      Qca-*)          build_qca ;;
      spidermonkey-*) build_spidermonkey ;;
      SPIRV-Headers-*) build_spirv_headers ;;
      SPIRV-Tools-*)  build_spirv_tools ;;
      SPIRV-LLVM-Translator-*) build_spirv_llvm_translator ;;
      Umockdev-*)     build_umockdev ;;
      utfcpp-*)       build_utfcpp ;;
      asciidoctor-*)    build_asciidoctor ;;
      bogofilter-*)     build_bogofilter ;;
      compface-*)       build_compface ;;
      desktop-file-utils-*) build_desktop_file_utils ;;
      dos2unix-*)       build_dos2unix ;;
      shaderc-*)        build_glslc ;;
  graphviz-*)       build_graphviz ;;
  pinentry-*)       build_pinentry ;;
  tree-*)           build_tree ;;
  xdg-dbus-proxy-*) build_xdg_dbus_proxy ;;
  gtk-doc-*)        build_gtk_doc ;;
  highlight-*)      build_highlight ;;
  ibus-*)           build_ibus ;;
  ImageMagick-*)    build_imagemagick ;;
  iso-codes-*)      build_iso_codes ;;
  lsof-*)           build_lsof ;;
  screen-*)         build_screen ;;
  shared-mime-info-*) build_shared_mime_info ;;
  sharutils-*)      build_sharutils ;;
  tidy-html5-*)     build_tidy_html5 ;;
  Time-[0-9]*|time-*) build_time_util ;;
  unixODBC-*)       build_unixodbc ;;
      xdg-user-dirs-*)  build_xdg_user_dirs ;;
      dbus-*)           build_dbus ;;
      pciutils-*)       build_pciutils ;;
      Sysstat-*)        build_sysstat ;;
      7zip-*)           build_7zip ;;
      AccountsService-*) build_accountsservice ;;
      acpid-*)          build_acpid ;;
      autofs-*)         build_autofs ;;
      hwdata-*)         build_hwdata ;;
      LSB-Tools-*)      build_lsb_tools ;;
      at-*)             build_at ;;
      Fcron-*)          build_fcron ;;
      Hdparm-*)         build_hdparm ;;
      GPM-*)            build_gpm ;;
      blocaled-*)       build_blocaled ;;
      Logrotate-*)      build_logrotate ;;
      MC-*)             build_mc ;;
      usbutils-*)       build_usbutils ;;
      xdotool-*)        build_xdotool ;;
      Zip-*)            build_zip ;;
      BlueZ-*)          build_bluez ;;
      Bubblewrap-*)     build_bubblewrap ;;
      Colord-*)         build_colord ;;
      notification-daemon-*) build_notification_daemon ;;
      cpio-*)           build_cpio ;;
      cups-pk-helper-*) build_cups_pk_helper ;;
      elogind-*)        build_elogind ;;
      lm-sensors-*)     build_lm_sensors ;;
      pm-utils-*)       build_pm_utils ;;
      power-profiles-daemon-*) build_power_profiles_daemon ;;
      ModemManager-*)   build_modemmanager ;;
      UDisks-*)         build_udisks ;;
      UPower-*)         build_upower ;;
      Which-*)          build_which ;;
      UnRar-*)          build_unrar ;;
      Pax-*)            build_pax ;;
      raptor-*)         build_raptor ;;
      Rasqal-*)         build_rasqal ;;
      Redland-*)        build_redland ;;
      sg3_utils-*)      build_sg3_utils ;;
      sysmond-*)        build_sysmond ;;
      sysmon3-*)        build_sysmon3 ;;
      NcFTP-*)          build_ncftp ;;
      ntp-*)            build_ntp ;;
      rpcbind-*)        build_rpcbind ;;
      Samba-*)          build_samba ;;
      iw-*)             build_iw ;;
      Wireless\ Tools-*) build_wireless_tools ;;
      wpa_supplicant-*) build_wpa_supplicant ;;
      CMake-*)          build_cmake ;;
      Lua-*)            build_lua ;;
      Mercurial-*)      build_mercurial ;;
      NASM-*)           build_nasm ;;
      PHP-*)            build_php ;;
      Clisp-*)          build_clisp ;;
      GCC-*)            build_gcc ;;
      GDB-*)            build_gdb ;;
      cargo-c-*)        build_cargo_c ;;
      Cbindgen-*)       build_cbindgen ;;
      Doxygen-*)        build_doxygen ;;
      Git-*)            build_git ;;
      dtc-*)            build_dtc ;;
      GC-*)             build_gc ;;
      patchelf-*)       build_patchelf ;;
      guile-*)          build_guile ;;
      luajit-*)         build_luajit ;;
      valgrind-*)       build_valgrind ;;
      LLVM-*)           build_llvm ;;
      OpenJDK-*)        build_openjdk ;;
      Java-*)           build_java_bin ;;
      Vala-*)           build_vala ;;
      yasm-*)           build_yasm ;;
      Ruby-*)           build_ruby ;;
      Rustc-*)          build_rustc ;;
      rust-bindgen-*)   build_rust_bindgen ;;
      SCons-*)          build_scons ;;
      slang-*)          build_slang ;;
      Subversion-*)     build_subversion ;;
      SWIG-*|swig-*)    build_swig ;;
      Tk-*)             build_tk ;;
      unifdef-*)        build_unifdef ;;
      apache-ant-*)     build_apache_ant ;;
      Python-3.11.*)    build_python3_11 ;;
      Python-*)         build_python3 ;;
      cssselect-*)      build_cssselect ;;
      Cython-*)         build_cython ;;
      docutils-*)       build_docutils ;;
      Net-tools-*)      build_net_tools ;;
      dhcpcd-*)         build_dhcpcd ;;
      bridge-utils-*)   build_bridge_utils ;;
      cifs-utils-*)     build_cifs_utils ;;
      NFS-Utils-*)      build_nfs_utils ;;
      rsync-*)          build_rsync ;;
      Avahi-*)          build_avahi ;;
      "BIND Utilities"*) build_bind_utils ;;
      NetworkManager-*) build_networkmanager ;;
      network-manager-applet-*) build_network_manager_applet ;;
      Nmap-*)           build_nmap ;;
      Traceroute-*)     build_traceroute ;;
      Whois-*)          build_whois ;;
      Wireshark-*)      build_wireshark ;;
      curl-*|cURL-*)    build_curl ;;
      c-ares-*)         build_c_ares ;;
      GeoClue-*)        build_geoclue ;;
      glib-networking-*) build_glib_networking ;;
      libevent-*)       build_libevent ;;
      libpcap-*)        build_libpcap ;;
      nghttp2-*)        build_nghttp2 ;;
      ldns-*)           build_ldns ;;
      libmnl-*)         build_libmnl ;;
      libndp-*)         build_libndp ;;
      libnma-*)         build_libnma ;;
      libsoup-3.*)      build_libsoup3 ;;
      libsoup-*)        build_libsoup ;;
      libpsl-*)         build_libpsl ;;
      libslirp-*)       build_libslirp ;;
      kdsoap-*)         build_kdsoap ;;
      kdsoap-ws-discovery-client-*) build_kdsoap_ws_discovery_client ;;
      libnl-*)          build_libnl ;;
      libnsl-*)         build_libnsl ;;
      libtirpc-*)       build_libtirpc ;;
      neon-*)           build_neon ;;
      rpcsvc-proto-*)   build_rpcsvc_proto ;;
      Serf-*)           build_serf ;;
      uhttpmock-*)      build_uhttpmock ;;
      Links-*)          build_links ;;
      Lynx-*)           build_lynx ;;
      Fetchmail-*)      build_fetchmail ;;
      mailx-*)          build_mailx ;;
      Mutt-*)           build_mutt ;;
      Procmail-*)       build_procmail ;;
      Apache-*)         build_apache ;;
      BIND-[0-9]*|BIND-*) build_bind ;;
      Kea-*)            build_kea ;;
      ProFTPD-*)        build_proftpd ;;
      Wget-*)           build_wget ;;
      Dash-*)           build_dash ;;
      Tcsh-*)           build_tcsh ;;
      zsh-*)            build_zsh ;;
      # Chapter 24: X Window System
      util-macros-*)     build_util_macros ;;
      xorgproto-*)       build_xorgproto ;;
      libXau-*)          build_libxau ;;
      libXdmcp-*)        build_libxdmcp ;;
      xcb-proto-*)       build_xcb_proto ;;
      libxcb-*)          build_libxcb ;;
      "Xorg Libraries"*) build_xorg_libraries ;;
      xcb-util-0.*)      build_xcb_util ;;
      "XCB Utilities"*)  build_xcb_util_extras ;;
      libxcvt-*)         build_libxcvt ;;
      libdrm-*)          build_libdrm ;;
      Mesa-*)            build_mesa ;;
      xbitmaps-*)        build_xbitmaps ;;
      "Xorg Applications"*) build_xorg_apps ;;
      luit-*)            build_luit ;;
      xcursor-themes-*)  build_xcursor_themes ;;
      XKeyboardConfig-*|xkeyboard-config-*) build_xkeyboard_config ;;
      "Xorg Fonts"*)     build_xorg_fonts ;;
      Xorg-Server-*|xorg-server-*) build_xorg_server ;;
      libevdev-*)        build_libevdev ;;
      "Xorg Evdev"*)     build_xf86_input_evdev ;;
      libinput-*)        build_libinput ;;
      "Xorg Libinput"*)  build_xf86_input_libinput ;;
      "Xorg Synaptics"*) build_xf86_input_synaptics ;;
      "Xorg Wacom"*)     build_xf86_input_wacom ;;
      Xwayland-*)        build_xwayland ;;
      xterm-*)           build_xterm ;;
      xclock-*)          build_xclock ;;
      twm-*)             build_twm ;;
      xinit-*)           build_xinit ;;
      "Xorg Legacy"*)    build_xorg_legacy ;;
      # Chapter 25: Graphical Environment Libraries
      at-spi2-core-*)    build_at_spi2_core ;;
      Atkmm-*)           build_atkmm ;;
      Cairo-*)           build_cairo ;;
      cairomm-*)         build_cairomm ;;
      colord-gtk-*)      build_colord_gtk ;;
      FLTK-*)            build_fltk ;;
      Freeglut-*)        build_freeglut ;;
      gdk-pixbuf-*)      build_gdk_pixbuf ;;
      GLEW-*)            build_glew ;;
      Glslang-*)         build_glslang ;;
      GLU-*)             build_glu ;;
      GOffice-*)         build_goffice ;;
      Graphene-*)        build_graphene ;;
      GTK-3.*|GTK+-3.*)  build_gtk3 ;;
      GTK-4.*|GTK+-4.*)  build_gtk4 ;;
      Gtkmm-*)           build_gtkmm ;;
      gtk-vnc-*)         build_gtk_vnc ;;
      gtksourceview-4.*) build_gtksourceview4 ;;
      GtkSourceView-5.*|gtksourceview-5.*) build_gtksourceview5 ;;
      imlib2-*)          build_imlib2 ;;
      keybinder-*)       build_keybinder3 ;;
      libadwaita-*)      build_libadwaita ;;
      libei-*)           build_libei ;;
      libepoxy-*)        build_libepoxy ;;
      libhandy-*)        build_libhandy ;;
      libnotify-*)       build_libnotify ;;
      Pango-*)           build_pango ;;
      Pangomm-*)         build_pangomm ;;
      Qt-*|qt-*)         build_qt6 ;;
      "Vulkan-Headers"*) build_vulkan_headers ;;
      "Vulkan-Loader"*)  build_vulkan_loader ;;
      WebKitGTK-*)       build_webkitgtk ;;
      xdg-desktop-portal-gtk-*) build_xdg_desktop_portal_gtk ;;
      xdg-desktop-portal-[0-9]*) build_xdg_desktop_portal ;;
      startup-notification-*) build_startup_notification ;;
      libxklavier-*)     build_libxklavier ;;
      kColorPicker-*)    build_kcolorpicker ;;
      kImageAnnotator-*) build_kimageannotator ;;
      # Chapter 21: Mail Server Software
      Dovecot-*)         build_dovecot ;;
      Exim-*)            build_exim ;;
      Postfix-*)         build_postfix ;;
      sendmail-*)        build_sendmail ;;
      # Chapter 22: Databases
      lmdb-*)            build_lmdb ;;
      MariaDB-*)         build_mariadb ;;
      PostgreSQL-*)      build_postgresql ;;
      SQLite-*)          build_sqlite ;;
      # Chapter 23: Other Server Software
      OpenLDAP-*)        build_openldap ;;
      Unbound-*)         build_unbound ;;
      *) run_package "$name" "$path" ;;
    esac
  done <<<"$packages"
}

# Chapter 5: File Systems and Disk Management

build_btrfs_progs() {
  run_step "btrfs-progs" bash -e <<'CMD'
./configure --prefix=/usr \
    --disable-static \
    --disable-documentation
make
make install
for i in 5 8; do install Documentation/*.$i /usr/share/man/man$i; done
CMD
}

build_dosfstools() {
  run_step "dosfstools" bash -e <<'CMD'
./configure --prefix=/usr \
    --enable-compat-symlinks \
    --mandir=/usr/share/man \
    --docdir=/usr/share/doc/dosfstools-4.2
make
make install
CMD
}

build_fuse() {
  run_step "Fuse" bash -e <<'CMD'
sed -i '/^udev/,$ s/^/#/' util/meson.build
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
chmod u+s /usr/bin/fusermount3
cd ..
cp -Rv doc/html -T /usr/share/doc/fuse-3.16.2
install -v -m644 doc/{README.NFS,kernel.txt} /usr/share/doc/fuse-3.16.2
CMD
}

build_jfsutils() {
  run_step "jfsutils" bash -e <<'CMD'
patch -Np1 -i ../jfsutils-1.1.15-gcc10_fix-1.patch
sed -i "/unistd.h/a#include <sys/types.h>"    fscklog/extract.c
sed -i "/ioctl.h/a#include <sys/sysmacros.h>" libfs/devices.c
./configure
make
make install
CMD
}

build_lvm2() {
  run_step "LVM2" bash -e <<'CMD'
PATH+=:/usr/sbin \
./configure --prefix=/usr \
    --enable-cmdlib \
    --enable-pkgconfig \
    --enable-udev_sync
make
make install
rm -fv /usr/lib/udev/rules.d/69-dm-lvm.rules
CMD
}

build_mdadm() {
  run_step "mdadm" bash -e <<'CMD'
make
make BINDIR=/usr/sbin install
CMD
}

build_ntfs_3g() {
  run_step "ntfs-3g" bash -e <<'CMD'
./configure --prefix=/usr \
    --disable-static \
    --with-fuse=internal \
    --docdir=/usr/share/doc/ntfs-3g-2022.10.3
make
make install
ln -sv ../bin/ntfs-3g /usr/sbin/mount.ntfs
ln -sv ntfs-3g.8 /usr/share/man/man8/mount.ntfs.8
CMD
}

build_gptfdisk() {
  run_step "gptfdisk" bash -e <<'CMD'
patch -Np1 -i ../gptfdisk-1.0.10-convenience-1.patch
sed -i 's|ncursesw/||' gptcurses.cc
sed -i 's|sbin|usr/sbin|' Makefile
make
make install
CMD
}

build_parted() {
  run_step "parted" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make -C doc html
makeinfo --html -o doc/html doc/parted.texi
makeinfo --plaintext -o doc/parted.txt doc/parted.texi
make install
install -v -m755 -d /usr/share/doc/parted-3.6/html
install -v -m644 doc/html/* /usr/share/doc/parted-3.6/html
install -v -m644 doc/{FAT,API,parted.{txt,html}} /usr/share/doc/parted-3.6
CMD
}

build_smartmontools() {
  run_step "smartmontools" bash -e <<'CMD'
./configure --prefix=/usr \
    --sysconfdir=/etc \
    --with-initscriptdir=no \
    --with-libsystemd=no \
    --docdir=/usr/share/doc/smartmontools-7.4
make
make install
CMD
}

build_sshfs() {
  run_step "sshfs" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_xfsprogs() {
  run_step "xfsprogs" bash -e <<'CMD'
sed -i 's/icu-i18n/icu-uc &/' configure
case "$(uname -m)" in
  i?86) sed -e "s/static long filesize/static off_t filesize/" -i mkfs/proto.c ;;
esac
make DEBUG=-DNDEBUG \
     INSTALL_USER=root \
     INSTALL_GROUP=root \
     LOCAL_CONFIGURE_OPTIONS="--localstatedir=/var"
make PKG_DOC_DIR=/usr/share/doc/xfsprogs-6.13.0 install
make PKG_DOC_DIR=/usr/share/doc/xfsprogs-6.13.0 install-dev
rm -rfv /usr/lib/libhandle.{a,la}
CMD
}

build_efivar() {
  run_step "efivar" bash -e <<'CMD'
make ENABLE_DOCS=0
make install ENABLE_DOCS=0 LIBDIR=/usr/lib
install -vm644 docs/efivar.1 /usr/share/man/man1
install -vm644 docs/*.3 /usr/share/man/man3
CMD
}

build_efibootmgr() {
  run_step "efibootmgr" bash -e <<'CMD'
make EFIDIR=LFS EFI_LOADER=grubx64.efi
make install EFIDIR=LFS
CMD
}

build_grub_efi() {
  run_step "GRUB-efi" bash -e <<'CMD'
mkdir -pv /usr/share/fonts/unifont
gunzip -c ../unifont-16.0.01.pcf.gz > /usr/share/fonts/unifont/unifont.pcf
unset {C,CPP,CXX,LD}FLAGS
echo "depends bli part_gpt" > grub-core/extra_deps.lst
./configure --prefix=/usr \
    --sysconfdir=/etc \
    --disable-efiemu \
    --with-platform=efi \
    --target=x86_64 \
    --disable-werror
make
make install
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
make -C grub-core install
install -vm755 grub-mkfont /usr/bin/
install -vm644 ascii.h widthspec.h *.pf2 /usr/share/grub/
install -vm755 grub-mount /usr/bin/
CMD
}

# Chapter 6: Text Editors

build_bluefish() {
  run_step "Bluefish" bash -e <<'CMD'
sed '/infbrowser/d' -i src/Makefile.am
autoreconf
./configure --prefix=/usr --docdir=/usr/share/doc/bluefish-2.2.16
make
make install
gtk-update-icon-cache -t -f --include-image-data /usr/share/icons/hicolor
update-desktop-database
CMD
}

build_ed() {
  run_step "Ed" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_emacs() {
  run_step "Emacs" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
chown -v -R root:root /usr/share/emacs/30.1
rm -vf /usr/lib/systemd/user/emacs.service
gtk-update-icon-cache -qtf /usr/share/icons/hicolor
CMD
}

build_gedit() {
  run_step "Gedit" bash -e <<'CMD'
tar -xf ../libgedit-gfls-0.2.1.tar.bz2
pushd libgedit-gfls-0.2.1
mkdir gfls-build
cd gfls-build
meson setup --prefix=/usr --buildtype=release -D gtk_doc=false ..
ninja
ninja install
popd

tar -xf ../libgedit-tepl-6.12.0.tar.bz2
pushd libgedit-tepl-6.12.0
mkdir tepl-build
cd tepl-build
meson setup --prefix=/usr --buildtype=release -D gtk_doc=false ..
ninja
ninja install
popd

mkdir gedit-build
cd gedit-build
meson setup --prefix=/usr --buildtype=release -D gtk_doc=false ..
ninja
ninja install
CMD
}

build_joe() {
  run_step "JOE" bash -e <<'CMD'
./configure --prefix=/usr \
    --sysconfdir=/etc \
    --docdir=/usr/share/doc/joe-4.6
make
make install
install -vm 755 joe/util/{stringify,termidx,uniproc} /usr/bin
CMD
}

build_kate() {
  run_step "kate" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=$KF6_PREFIX \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_TESTING=OFF \
      -W no-dev ..
make
make install
CMD
}

build_mousepad() {
  run_step "Mousepad" bash -e <<'CMD'
./configure --prefix=/usr \
    --enable-gtksourceview4 \
    --enable-keyfile-settings
make
make install
CMD
}

build_nano() {
  run_step "Nano" bash -e <<'CMD'
./configure --prefix=/usr \
    --sysconfdir=/etc \
    --enable-utf8 \
    --docdir=/usr/share/doc/nano-8.3
make
make install
install -v -m644 doc/{nano.html,sample.nanorc} /usr/share/doc/nano-8.3
CMD
}

build_vim() {
  run_step "Vim" bash -e <<'CMD'
echo '#define SYS_VIMRC_FILE  "/etc/vimrc"' >> src/feature.h
echo '#define SYS_GVIMRC_FILE "/etc/gvimrc"' >> src/feature.h
./configure --prefix=/usr \
    --with-features=huge \
    --enable-gui=gtk3 \
    --with-tlib=ncursesw
make
make install
ln -snfv ../vim/vim91/doc /usr/share/doc/vim-9.1.1166
CMD
}

# Chapter 7: Shells

build_dash() {
  run_step "Dash" bash -e <<'CMD'
./configure --bindir=/bin --mandir=/usr/share/man
make
make install
cat >> /etc/shells <<'EOF'
/bin/dash
EOF
CMD
}

build_tcsh() {
  run_step "Tcsh" bash -e <<'CMD'
./configure --prefix=/usr
make
make install install.man
ln -v -sf tcsh   /bin/csh
ln -v -sf tcsh.1 /usr/share/man/man1/csh.1
cat >> /etc/shells <<'EOF'
/bin/tcsh
/bin/csh
EOF
CMD
}

build_zsh() {
  run_step "zsh" bash -e <<'CMD'
sed -e 's/set_from_init_file/texinfo_&/' -i Doc/Makefile.in
sed -e 's/^main/int &/' \
    -e 's/exit(/return(/' -i aczsh.m4 configure.ac
sed -e 's/test = /&(char**)/' -i configure.ac
autoconf
sed -e 's|/etc/z|/etc/zsh/z|g' -i Doc/*.*
./configure --prefix=/usr \
    --sysconfdir=/etc/zsh \
    --enable-etcdir=/etc/zsh \
    --enable-cap \
    --enable-gdbm
make
makeinfo  Doc/zsh.texi --html      -o Doc/html
makeinfo  Doc/zsh.texi --plaintext -o zsh.txt
makeinfo  Doc/zsh.texi --html --no-split --no-headers -o zsh.html
if command -v texi2pdf >/dev/null; then
  texi2pdf Doc/zsh.texi -o Doc/zsh.pdf || true
fi
make install
make infodir=/usr/share/info install.info
make htmldir=/usr/share/doc/zsh-5.9/html install.html
install -v -m644 zsh.{html,txt} Etc/FAQ /usr/share/doc/zsh-5.9
if [ -f Doc/zsh.pdf ]; then
  install -v -m644 Doc/zsh.pdf /usr/share/doc/zsh-5.9
fi
cat >> /etc/shells <<'EOF'
/bin/zsh
EOF
CMD
}

# Chapter 8: Virtualization

build_qemu() {
  run_step "qemu" bash -e <<'CMD'
if [ $(uname -m) = i686 ]; then
  QEMU_ARCH=i386-softmmu
else
  QEMU_ARCH=x86_64-softmmu
fi

mkdir -vp build &&
cd        build &&

../configure --prefix=/usr               \
             --sysconfdir=/etc           \
             --localstatedir=/var        \
             --target-list=$QEMU_ARCH    \
             --audio-drv-list=alsa       \
             --disable-pa                \
             --enable-slirp              \
             --docdir=/usr/share/doc/qemu-9.2.2 &&

unset QEMU_ARCH &&
make
make install
chgrp kvm  /usr/libexec/qemu-bridge-helper
chmod 4750 /usr/libexec/qemu-bridge-helper
ln -sv qemu-system-$(uname -m) /usr/bin/qemu
CMD
}

# Chapter 9: General Libraries

build_abseil_cpp() {
  run_step "abseil-cpp" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D ABSL_PROPAGATE_CXX_STD=ON \
      -D BUILD_SHARED_LIBS=ON      \
      -G Ninja ..
ninja
ninja install
CMD
}

build_appstream() {
  run_step "appstream" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D apidocs=false \
            -D stemming=false ..
ninja
ninja install
mv -v /usr/share/doc/appstream{,-1.0.4}
install -vdm755 /usr/share/metainfo
cat > /usr/share/metainfo/org.linuxfromscratch.lfs.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<component type="operating-system">
  <id>org.linuxfromscratch.lfs</id>
  <name>Linux From Scratch</name>
  <summary>A customized Linux system built entirely from source</summary>
  <description>
    <p>
      Linux From Scratch (LFS) is a project that provides you with
      step-by-step instructions for building your own customized Linux
      system entirely from source.
    </p>
  </description>
  <url type="homepage">https://www.linuxfromscratch.org/lfs/</url>
  <metadata_license>MIT</metadata_license>
  <developer id='linuxfromscratch.org'>
    <name>The Linux From Scratch Editors</name>
  </developer>
  <releases>
    <release version="12.3" type="release" date="2025-03-05">
      <description>
        <p>The development snapshot of the next LFS version.</p>
      </description>
    </release>
    <release version="12.2" type="stable" date="2024-09-01">
      <description>
        <p>Now contains Binutils 2.43.1, GCC-14.2.0, Glibc-2.40,
        and Linux kernel 6.10.</p>
      </description>
    </release>
  </releases>
</component>
EOF
CMD
}

build_appstream_glib() {
  run_step "appstream-glib" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D rpm=false
ninja
ninja install
CMD
}

build_apr() {
  run_step "Apr" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --with-installbuilddir=/usr/share/apr-1/build
make
make install
CMD
}

build_apr_util() {
  run_step "Apr-Util" bash -e <<'CMD'
./configure --prefix=/usr \
            --with-apr=/usr \
            --with-gdbm=/usr \
            --with-openssl=/usr \
            --with-crypto
make
make install
CMD
}

build_boost() {
  run_step "boost" bash -e <<'CMD'
case $(uname -m) in
   i?86)
      sed -e "s/defined(__MINGW32__)/& || defined(__i386__)/" \
          -i ./libs/stacktrace/src/exception_headers.h ;;
esac
./bootstrap.sh --prefix=/usr --with-python=python3
./b2 stage -j$(nproc) threading=multi link=shared
./b2 install threading=multi link=shared
rm -rf /usr/lib/cmake/[Bb]oost*
CMD
}

build_brotli() {
  run_step "brotli" bash -e <<'CMD'
mkdir build &&
cd    build &&
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  .. &&
make
make install
cd .. &&
sed "/c\/.*\.[ch]'\/d;/include_dirs=\[/i libraries=['brotlicommon','brotlidec','brotlienc']," -i setup.py
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links dist --no-user Brotli
CMD
}

build_libarchive() {
  run_step "libarchive" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
ln -sfv bsdunzip /usr/bin/unzip
CMD
}

build_libassuan() {
  run_step "libassuan" bash -e <<'CMD'
./configure --prefix=/usr
make
make -C doc html
makeinfo --html --no-split -o doc/assuan_nochunks.html doc/assuan.texi
makeinfo --plaintext -o doc/assuan.txt doc/assuan.texi
make -C doc pdf ps
make install
install -v -dm755   /usr/share/doc/libassuan-3.0.2/html
install -v -m644 doc/assuan.html/* \
                /usr/share/doc/libassuan-3.0.2/html
install -v -m644 doc/assuan_nochunks.html \
                /usr/share/doc/libassuan-3.0.2
install -v -m644 doc/assuan.{txt,texi} \
                /usr/share/doc/libassuan-3.0.2
install -v -m644  doc/assuan.{pdf,ps,dvi} \
                /usr/share/doc/libassuan-3.0.2
CMD
}

build_libgpg_error() {
  run_step "libgpg-error" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
install -v -m644 -D README /usr/share/doc/libgpg-error-1.51/README
CMD
}

build_libgcrypt() {
  run_step "libgcrypt" bash -e <<'CMD'
./configure --prefix=/usr
make
make -C doc html
makeinfo --html --no-split -o doc/gcrypt_nochunks.html doc/gcrypt.texi
makeinfo --plaintext -o doc/gcrypt.txt doc/gcrypt.texi
make install
install -v -dm755   /usr/share/doc/libgcrypt-1.11.0/html
install -v -m644 doc/gcrypt.html/* \
                /usr/share/doc/libgcrypt-1.11.0/html
install -v -m644 doc/gcrypt_nochunks.html \
                /usr/share/doc/libgcrypt-1.11.0
install -v -m644 doc/gcrypt.{txt,texi} \
                /usr/share/doc/libgcrypt-1.11.0
install -v -m644 README doc/{README.apichanges,fips*,libgcrypt*} \
                /usr/share/doc/libgcrypt-1.11.0
CMD
}

build_libxml2() {
  run_step "libxml2" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static \
            --with-history \
            --with-icu \
            PYTHON=/usr/bin/python3 \
            --docdir=/usr/share/doc/libxml2-2.13.6
make
make install
rm -vf /usr/lib/libxml2.la
sed '/libs=/s/xml2.*/xml2"/' -i /usr/bin/xml2-config
CMD
}

build_pcre2() {
  run_step "PCRE2" bash -e <<'CMD'
./configure --prefix=/usr \
            --docdir=/usr/share/doc/pcre2-10.45 \
            --enable-unicode \
            --enable-jit \
            --enable-pcre2-16 \
            --enable-pcre2-32 \
            --enable-pcre2grep-libz \
            --enable-pcre2grep-libbz2 \
            --enable-pcre2test-libreadline \
            --disable-static
make
make install
CMD
}

build_fast_float() {
  run_step "fast_float" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -G Ninja ..
ninja
ninja install
CMD
}

build_libproxy() {
  run_step "libproxy" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D release=true ..
ninja
ninja install
CMD
}

# Chapter 10: Graphics and Font Libraries

build_aalib() {
  run_step "AAlib" bash -e <<'CMD'
sed -i -e '/AM_PATH_AALIB,/s/AM_PATH_AALIB/[&]/' aalib.m4
sed -e 's/8x13bold/-*-luxi mono-bold-r-normal--13-120-*-*-m-*-*-*/' \
    -i src/aax.c
sed 's/stdscr->_max\([xy]\) + 1/getmax\1(stdscr)/' \
    -i src/aacurses.c
sed -i '1i#include <stdlib.h>' \
    src/aa{fire,info,lib,linuxkbd,savefont,test,regist}.c
sed -i '1i#include <string.h>' \
    src/aa{kbdreg,moureg,test,regist}.c
sed -i '/X11_KBDDRIVER/a#include <X11/Xutil.h>' \
    src/aaxkbd.c
sed -i '/rawmode_init/,/^}/s/return;/return 0;/' \
    src/aalinuxkbd.c
autoconf
./configure --prefix=/usr \
            --infodir=/usr/share/info \
            --mandir=/usr/share/man \
            --with-ncurses=/usr \
            --disable-static
make
  make install
CMD
}

# Additional Chapter 9 libraries

build_aspell() {
  run_step "Aspell" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
ln -svfn aspell-0.60 /usr/lib/aspell
install -v -m755 -d /usr/share/doc/aspell-0.60.8.1/aspell{,-dev}.html
install -v -m644 manual/aspell.html/* /usr/share/doc/aspell-0.60.8.1/aspell.html
install -v -m644 manual/aspell-dev.html/* /usr/share/doc/aspell-0.60.8.1/aspell-dev.html
CMD
}

build_clucene() {
  run_step "CLucene" bash -e <<'CMD'
patch -Np1 -i ../clucene-2.3.3.4-contribs_lib-1.patch
sed -i '/Misc.h/a #include <ctime>' src/core/CLucene/document/DateTools.cpp
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr -D BUILD_CONTRIBS_LIB=ON ..
make
make install
CMD
}

build_dbus_glib() {
  run_step "dbus-glib" bash -e <<'CMD'
./configure --prefix=/usr --sysconfdir=/etc --disable-static
make
make install
CMD
}

build_double_conversion() {
  run_step "double-conversion" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D BUILD_SHARED_LIBS=ON \
      -D BUILD_TESTING=ON ..
make
make install
CMD
}

build_duktape() {
  run_step "duktape" bash -e <<'CMD'
sed -i 's/-Os/-O2/' Makefile.sharedlibrary
make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr
make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr install
CMD
}

build_enchant() {
  run_step "enchant" bash -e <<'CMD'
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/enchant-2.8.2
make
make install
CMD
}

build_exempi() {
  run_step "Exempi" bash -e <<'CMD'
sed -i -r '/^\s?testadobesdk/d' exempi/Makefile.am
autoreconf -fiv
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_fftw() {
  run_step "fftw" bash -e <<'CMD'
./configure --prefix=/usr    \
            --enable-shared  \
            --disable-static \
            --enable-threads \
            --enable-sse2    \
            --enable-avx     \
            --enable-avx2
make
make install
make clean
./configure --prefix=/usr    \
            --enable-shared  \
            --disable-static \
            --enable-threads \
            --enable-sse2    \
            --enable-avx     \
            --enable-avx2    \
            --enable-float
make
make install
make clean
./configure --prefix=/usr    \
            --enable-shared  \
            --disable-static \
            --enable-threads \
            --enable-long-double
make
make install
CMD
}

build_fmt() {
  run_step "fmt" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_INSTALL_LIBDIR=/usr/lib \
      -D BUILD_SHARED_LIBS=ON \
      -D FMT_TEST=OFF \
      -G Ninja ..
ninja
ninja install
CMD
}

build_glib() {
  run_step "GLib" bash -e <<'CMD'
patch -Np1 -i ../glib-skip_warnings-1.patch
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release -D introspection=disabled -D glib_debug=disabled -D man-pages=enabled -D sysprof=disabled
ninja
ninja install
CMD
}

build_glibmm() {
  run_step "glibmm" bash -e <<'CMD'
mkdir bld
cd bld
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_gmime() {
  run_step "GMime" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_gspell() {
  run_step "gspell" bash -e <<'CMD'
mkdir gspell-build
cd gspell-build
meson setup --prefix=/usr --buildtype=release -D gtk_doc=false ..
ninja
ninja install
CMD
}

build_highway() {
  run_step "highway" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_TESTING=OFF \
      -D BUILD_SHARED_LIBS=ON \
      -G Ninja ..
ninja
ninja install
CMD
}

build_icu() {
  run_step "icu" bash -e <<'CMD'
cd source
./configure --prefix=/usr
make
make install
CMD
}

build_json_c() {
  run_step "JSON-C" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_STATIC_LIBS=OFF ..
make
make install
CMD
}

build_keyutils() {
  run_step "keyutils" bash -e <<'CMD'
make
make NO_ARLIB=1 LIBDIR=/usr/lib BINDIR=/usr/bin SBINDIR=/usr/sbin install
make -k test || true
CMD
}

build_libaio() {
  run_step "libaio" bash -e <<'CMD'
sed -i '/install.*libaio.a/s/^/#/' src/Makefile
make
make install
CMD
}

build_libatasmart() {
  run_step "libatasmart" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make docdir=/usr/share/doc/libatasmart-0.19 install
CMD
}

build_libdaemon() {
  run_step "libdaemon" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make docdir=/usr/share/doc/libdaemon-0.14 install
CMD
}

build_nodejs() {
  run_step "Node.js" bash -e <<'CMD'
./configure --prefix=/usr \
            --shared-brotli \
            --shared-cares \
            --shared-libuv \
            --shared-openssl \
            --shared-nghttp2 \
            --shared-zlib \
            --with-intl=system-icu
make
make install
ln -sf node /usr/share/doc/node-22.14.0
CMD
}

build_nspr() {
  run_step "NSPR" bash -e <<'CMD'
cd nspr
sed -i '/^RELEASE/s|^|#|' pr/src/misc/Makefile.in
sed -i 's|$(LIBRARY) ||'  config/rules.mk
./configure --prefix=/usr --with-mozilla --with-pthreads $( [ $(uname -m) = x86_64 ] && echo --enable-64bit )
make
make install
CMD
}

build_protobuf() {
  run_step "Protobuf" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D protobuf_BUILD_TESTS=OFF \
      -D protobuf_ABSL_PROVIDER=package \
      -D protobuf_BUILD_LIBUPB=OFF \
      -D protobuf_BUILD_SHARED_LIBS=ON \
      -G Ninja ..
ninja
ninja install
CMD
}

build_qcoro() {
  run_step "qcoro" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=$QT6DIR \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_TESTING=OFF \
      -D QCORO_BUILD_EXAMPLES=OFF \
      -D BUILD_SHARED_LIBS=ON ..
make
make install
CMD
}

build_talloc() {
  run_step "Talloc" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_uchardet() {
  run_step "Uchardet" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr -D BUILD_STATIC=OFF -W no-dev ..
make
make install
CMD
}

build_wayland() {
  run_step "Wayland" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release -D documentation=false
ninja
ninja install
CMD
}

build_wayland_protocols() {
  run_step "Wayland-Protocols" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_wv() {
  run_step "wv" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_xapian() {
  run_step "Xapian" bash -e <<'CMD'
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xapian-core-1.4.27
make
make install
CMD
}

build_freetype() {
  run_step "FreeType" bash -e <<'CMD'
tar -xf ../freetype-doc-2.13.3.tar.xz --strip-components=2 -C docs
sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" \
    -i include/freetype/config/ftoption.h
./configure --prefix=/usr --enable-freetype-config --disable-static
make
make install
cp -v -R docs -T /usr/share/doc/freetype-2.13.3
rm -v /usr/share/doc/freetype-2.13.3/freetype-config.1
CMD
}

build_fontconfig() {
  run_step "fontconfig" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-docs \
            --docdir=/usr/share/doc/fontconfig-2.16.0
make
make install
install -v -dm755 /usr/share/{man/man{1,3,5},doc/fontconfig-2.16.0}
install -v -m644 fc-*/*.1         /usr/share/man/man1
install -v -m644 doc/*.3          /usr/share/man/man3
install -v -m644 doc/fonts-conf.5 /usr/share/man/man5
install -v -m644 doc/*.{pdf,sgml,txt,html} \
               /usr/share/doc/fontconfig-2.16.0
CMD
}

build_harfbuzz() {
  run_step "harfbuzz" bash -e <<'CMD'
mkdir build &&
cd    build &&
meson setup .. --prefix=/usr --buildtype=release -D graphite2=enabled
ninja
ninja install
CMD
}

build_libpng() {
  run_step "libpng" bash -e <<'CMD'
gzip -cd ../libpng-1.6.46-apng.patch.gz | patch -p1
./configure --prefix=/usr --disable-static
make
make install
mkdir -v /usr/share/doc/libpng-1.6.46
cp -v README libpng-manual.txt /usr/share/doc/libpng-1.6.46
CMD
}

build_libtiff() {
  run_step "libtiff" bash -e <<'CMD'
mkdir -p libtiff-build &&
cd       libtiff-build &&
cmake -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/libtiff-4.7.0 \
      -D CMAKE_INSTALL_PREFIX=/usr -G Ninja .. &&
ninja
ninja install
CMD
}

build_libmng() {
  run_step "libmng" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
install -v -m755 -d /usr/share/doc/libmng-2.0.3
install -v -m644 doc/*.txt /usr/share/doc/libmng-2.0.3
CMD
}

build_libmypaint() {
  run_step "libmypaint" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_libraw() {
  run_step "libraw" bash -e <<'CMD'
./configure --prefix=/usr \
            --enable-jpeg \
            --enable-jasper \
            --enable-lcms \
            --disable-static \
            --docdir=/usr/share/doc/libraw-0.21.3
make
make install
CMD
}

build_librsvg() {
  run_step "librsvg" bash -e <<'CMD'
sed -e "/OUTDIR/s|,| / 'librsvg-2.59.2', '--no-namespace-dir',|" \
    -e '/output/s|Rsvg-2.0|librsvg-2.59.2|' \
    -i doc/meson.build
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libspiro() {
  run_step "libspiro" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_libwebp() {
  run_step "libwebp" bash -e <<'CMD'
./configure --prefix=/usr           \
            --enable-libwebpmux     \
            --enable-libwebpdemux   \
            --enable-libwebpdecoder \
            --enable-libwebpextras  \
            --enable-swap-16bit-csp \
            --disable-static
make
make install
CMD
}

build_mypaint_brushes() {
  run_step "mypaint-brushes" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_newt() {
  run_step "newt" bash -e <<'CMD'
sed -e '/install -m 644 $(LIBNEWT)/ s/^/#/' \
    -e '/$(LIBNEWT):/,/rv/ s/^/#/'          \
    -e 's/$(LIBNEWT)/$(LIBNEWTSH)/g'        \
    -i Makefile.in
./configure --prefix=/usr \
            --with-gpm-support \
            --with-python=python3.13
make
make install
CMD
}

build_opencv() {
  run_step "opencv" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr      \
      -D CMAKE_BUILD_TYPE=Release       \
      -D ENABLE_CXX11=ON                \
      -D BUILD_PERF_TESTS=OFF           \
      -D WITH_XINE=ON                   \
      -D BUILD_TESTS=OFF                \
      -D ENABLE_PRECOMPILED_HEADERS=OFF \
      -D CMAKE_SKIP_INSTALL_RPATH=ON    \
      -D BUILD_WITH_DEBUG_INFO=OFF      \
      -D OPENCV_GENERATE_PKGCONFIG=ON   \
      -W no-dev  ..
make
make install
CMD
}

build_openjpeg() {
  run_step "OpenJPEG" bash -e <<'CMD'
mkdir -v build
cd       build
cmake -D CMAKE_BUILD_TYPE=Release  \
      -D CMAKE_INSTALL_PREFIX=/usr \
      -D BUILD_STATIC_LIBS=OFF ..
make
make install
cp -rv ../doc/man -T /usr/share/man
CMD
}

build_pixman() {
  run_step "Pixman" bash -e <<'CMD'
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_poppler() {
  run_step "Poppler" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_BUILD_TYPE=Release   \
      -D CMAKE_INSTALL_PREFIX=/usr  \
      -D TESTDATADIR=$PWD/testfiles \
      -D ENABLE_QT5=OFF             \
      -D ENABLE_UNSTABLE_API_ABI_HEADERS=ON \
      -G Ninja ..
ninja
ninja install
install -v -m755 -d /usr/share/doc/poppler-25.02.0
cp -vr ../glib/reference/html /usr/share/doc/poppler-25.02.0
CMD
}

build_potrace() {
  run_step "Potrace" bash -e <<'CMD'
./configure --prefix=/usr                        \
            --disable-static                     \
            --docdir=/usr/share/doc/potrace-1.16 \
            --enable-a4                          \
            --enable-metric                      \
            --with-libpotrace
make
make install
CMD
}

build_qpdf() {
  run_step "Qpdf" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D BUILD_STATIC_LIBS=OFF     \
      -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/qpdf-11.10.1 \
      ..
make
make install
CMD
}

build_qrencode() {
  run_step "qrencode" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_sassc() {
  run_step "sassc" bash -e <<'CMD'
tar -xf ../libsass-3.6.6.tar.gz
pushd libsass-3.6.6
autoreconf -fi
./configure --prefix=/usr --disable-static
make
make install
popd
autoreconf -fi
./configure --prefix=/usr
make
make install
CMD
}

build_webp_pixbuf_loader() {
  run_step "webp-pixbuf-loader" bash -e <<'CMD'
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
gdk-pixbuf-query-loaders --update-cache
CMD
}

build_woff2() {
  run_step "woff2" bash -e <<'CMD'
mkdir out
cd    out
cmake -D CMAKE_INSTALL_PREFIX=/usr   \
      -D CMAKE_BUILD_TYPE=Release    \
      -D CMAKE_SKIP_INSTALL_RPATH=ON ..
make
make install
CMD
}

build_zxing_cpp() {
  run_step "zxing-cpp" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D ZXING_EXAMPLES=OFF        \
      -W no-dev ..
make
make install
CMD
}

# Chapter 11: General Utilities
build_gmmlib() {
  run_step "gmmlib" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D BUILD_TYPE=Release \
      -G Ninja \
      -W no-dev ..
ninja
ninja install
CMD
}

build_gsl() {
  run_step "gsl" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_inih() {
  run_step "inih" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_jansson() {
  run_step "Jansson" bash -e <<'CMD'
sed -e "/DT/s;| sort;| sed 's/@@libjansson.*//' &;" -i test/suites/api/check-exports
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_json_glib() {
  run_step "JSON-GLib" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libatomic_ops() {
  run_step "libatomic_ops" bash -e <<'CMD'
./configure --prefix=/usr \
            --enable-shared \
            --disable-static \
            --docdir=/usr/share/doc/libatomic_ops-7.8.2
make
make install
CMD
}

build_libblockdev() {
  run_step "libblockdev" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --with-python3 \
            --without-escrow \
            --without-gtk-doc \
            --without-lvm \
            --without-lvm_dbus \
            --without-nvdimm \
            --without-tools
make
make install
CMD
}

build_libbytesize() {
  run_step "libbytesize" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_libclc() {
  run_step "libclc" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -G Ninja ..
ninja
ninja install
CMD
}

build_libcloudproviders() {
  run_step "libcloudproviders" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libdisplay_info() {
  run_step "libdisplay-info" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libgsf() {
  run_step "libgsf" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_libgudev() {
  run_step "libgudev" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libgusb() {
  run_step "libgusb" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D docs=false
ninja
ninja install
CMD
}

build_libical() {
  run_step "libical" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D SHARED_ONLY=yes \
      -D ICAL_BUILD_DOCS=false \
      -D ICAL_BUILD_EXAMPLES=false \
      -D GOBJECT_INTROSPECTION=true \
      -D ICAL_GLIB_VAPI=true ..
make
make install
CMD
}

build_libidn() {
  run_step "libidn" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make check || true
make install
find doc -name "Makefile*" -delete
rm -rf doc/{gdoc,idn.1,stamp-vti,man,texi}
mkdir -v /usr/share/doc/libidn-1.42
cp -r -v doc/* /usr/share/doc/libidn-1.42
CMD
}

build_libidn2() {
  run_step "libidn2" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_libksba() {
  run_step "libksba" bash -e <<'CMD'
./configure --prefix=/usr
make
make check
make install
CMD
}

build_liblinear() {
  run_step "liblinear" bash -e <<'CMD'
make lib
install -vm644 linear.h /usr/include
install -vm755 liblinear.so.6 /usr/lib
ln -sfv liblinear.so.6 /usr/lib/liblinear.so
CMD
}

build_libmbim() {
  run_step "libmbim" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_libnvme() {
  run_step "libnvme" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -D libdbus=auto ..
ninja
ninja install
CMD
}

build_libpaper() {
  run_step "libpaper" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static \
            --docdir=/usr/share/doc/libpaper-2.2.6
make
make install
CMD
}

build_libportal() {
  run_step "libportal" bash -e <<'CMD'
if [ -e /usr/include/libportal ]; then
  rm -rf /usr/include/libportal.old
  mv -vf /usr/include/libportal{,.old}
fi
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -D docs=false ..
ninja
ninja install
CMD
}

build_libptytty() {
  run_step "libptytty" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D PT_UTMP_FILE:STRING=/run/utmp ..
make
make install
CMD
}

build_libqalculate() {
  run_step "libqalculate" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/libqalculate-5.5.1
make
make check || true
make install
rm -v /usr/lib/libqalculate.la
CMD
}

build_libqmi() {
  run_step "libqmi" bash -e <<'CMD'
PYTHON=python3 ./configure --prefix=/usr --disable-static
make
make check || true
make install
CMD
}

build_libseccomp() {
  run_step "libseccomp" bash -e <<'CMD'
  ./configure --prefix=/usr --disable-static
  make
  make check
  make install
CMD
}

build_libsigc2() {
  run_step "libsigc++2" bash -e <<'CMD'
mkdir bld
cd bld
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libsigc3() {
  run_step "libsigc++3" bash -e <<'CMD'
mkdir bld
cd bld
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libsigsegv() {
  run_step "libsigsegv" bash -e <<'CMD'
./configure --prefix=/usr \
            --enable-shared \
            --disable-static
make
make check
make install
CMD
}

build_libssh2() {
  run_step "libssh2" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-docker-tests \
            --disable-static
make
make check
make install
CMD
}

build_libstatgrab() {
  run_step "libstatgrab" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/libstatgrab-0.92.1
make
make check
make install
CMD
}

build_libtasn1() {
  run_step "libtasn1" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make check
make install
CMD
}

build_libunistring() {
  run_step "libunistring" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/libunistring-1.3
make
make check
make install
CMD
}

build_libunwind() {
  run_step "libunwind" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make check
make install
CMD
}

build_liburcu() {
  run_step "liburcu" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/liburcu-0.15.1
make
make check
make install
CMD
}

build_libusb() {
  run_step "libusb" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_libuv() {
  run_step "libuv" bash -e <<'CMD'
sh autogen.sh
./configure --prefix=/usr --disable-static
make
make man -C docs || true
make install
CMD
}

build_libxkbcommon() {
  run_step "libxkbcommon" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release -D enable-docs=false
ninja
ninja install
CMD
}

build_libxmlb() {
  run_step "libxmlb" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -D gtkdoc=false ..
ninja
ninja install
CMD
}

build_libxslt() {
  run_step "libxslt" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --docdir=/usr/share/doc/libxslt-1.1.42
make
make check
make install
CMD
}

build_libwacom() {
  run_step "libwacom" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release -D tests=disabled
ninja
ninja install
CMD
}

build_libyaml() {
  run_step "libyaml" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_log4cplus() {
  run_step "log4cplus" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_lzo() {
  run_step "LZO" bash -e <<'CMD'
./configure --prefix=/usr \
            --enable-shared \
            --disable-static \
            --docdir=/usr/share/doc/lzo-2.10
make
make install
CMD
}

build_mtdev() {
  run_step "mtdev" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_npth() {
  run_step "npth" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_popt() {
  run_step "Popt" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_protobuf_c() {
  run_step "Protobuf-c" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_qca() {
  run_step "Qca" bash -e <<'CMD'
sed -i 's@cert.pem@certs/ca-bundle.crt@' CMakeLists.txt
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=$QT6DIR \
      -D CMAKE_BUILD_TYPE=Release \
      -D QT6=ON \
      -D QCA_INSTALL_IN_QT_PREFIX=ON \
      -D QCA_MAN_INSTALL_DIR:PATH=/usr/share/man \
      ..
make
make install
CMD
}

build_spidermonkey() {
  run_step "spidermonkey" bash -e <<'CMD'
sed -i 's/icu-i18n/icu-uc &/' js/moz.configure
mkdir obj
cd obj
../js/src/configure --prefix=/usr \
                    --disable-debug-symbols \
                    --disable-jemalloc \
                    --enable-readline \
                    --enable-rust-simd \
                    --with-intl-api \
                    --with-system-icu \
                    --with-system-zlib
make
rm -fv /usr/lib/libmozjs-128.so || true
make install
rm -v /usr/lib/libjs_static.ajs
sed -i '/@NSPR_CFLAGS@/d' /usr/bin/js128-config
CMD
}

build_spirv_headers() {
  run_step "SPIRV-Headers" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr -G Ninja ..
ninja
ninja install
CMD
}

build_spirv_tools() {
  run_step "SPIRV-Tools" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D SPIRV_WERROR=OFF \
      -D BUILD_SHARED_LIBS=ON \
      -D SPIRV_TOOLS_BUILD_STATIC=OFF \
      -D SPIRV-Headers_SOURCE_DIR=/usr \
      -G Ninja ..
ninja
ninja install
CMD
}

build_spirv_llvm_translator() {
  run_step "SPIRV-LLVM-Translator" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_SHARED_LIBS=ON \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=/usr \
      -G Ninja ..
ninja
ninja install
CMD
}

build_umockdev() {
  run_step "Umockdev" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
  ninja install
CMD
}

build_babl() {
  run_step "babl" bash -e <<'CMD'
mkdir bld
cd    bld
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
install -v -m755 -d /usr/share/gtk-doc/html/babl/graphics
install -v -m644 docs/*.{css,html} /usr/share/gtk-doc/html/babl
install -v -m644 docs/graphics/*.{html,svg} /usr/share/gtk-doc/html/babl/graphics
CMD
}

build_exiv2() {
  run_step "Exiv2" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D EXIV2_ENABLE_VIDEO=yes \
      -D EXIV2_ENABLE_WEBREADY=yes \
      -D EXIV2_ENABLE_CURL=yes \
      -D EXIV2_BUILD_SAMPLES=no \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -G Ninja ..
ninja
ninja install
CMD
}

build_fribidi() {
  run_step "FriBidi" bash -e <<'CMD'
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_gegl() {
  run_step "gegl" bash -e <<'CMD'
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_giflib() {
  run_step "giflib" bash -e <<'CMD'
patch -Np1 -i ../giflib-5.2.2-upstream_fixes-1.patch
cp pic/gifgrid.gif doc/giflib-logo.gif
make
make PREFIX=/usr install
rm -fv /usr/lib/libgif.a
find doc \( -name Makefile\* -o -name '*.1' -o -name '*.xml' \) -exec rm -v {} \;
install -v -dm755 /usr/share/doc/giflib-5.2.2
cp -v -R doc/* /usr/share/doc/giflib-5.2.2
CMD
}

build_glad() {
  run_step "Glad" bash -e <<'CMD'
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links dist --no-user glad2
CMD
}

build_glm() {
  run_step "GLM" bash -e <<'CMD'
cp -r glm /usr/include/
cp -r doc /usr/share/doc/glm-1.0.1
CMD
}

build_graphite2() {
  run_step "Graphite2" bash -e <<'CMD'
sed -i '/cmptest/d' tests/CMakeLists.txt
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr ..
make
make install
CMD
}

build_jasper() {
  run_step "jasper" bash -e <<'CMD'
mkdir BUILD
cd    BUILD
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D JAS_ENABLE_DOC=NO \
      -D ALLOW_IN_SOURCE_BUILD=YES \
      -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/jasper-4.2.4 \
      ..
make
make install
CMD
}

build_lcms2() {
  run_step "lcms2" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_libavif() {
  run_step "libavif" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D AVIF_CODEC_AOM=SYSTEM \
      -D AVIF_BUILD_GDK_PIXBUF=ON \
      -D AVIF_LIBYUV=OFF \
      -G Ninja ..
ninja
ninja install
gdk-pixbuf-query-loaders --update-cache
CMD
}

build_libexif() {
  run_step "libexif" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --with-doc-dir=/usr/share/doc/libexif-0.6.25
make
make install
CMD
}

build_libgxps() {
  run_step "libgxps" bash -e <<'CMD'
mkdir build
cd    build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libjpeg_turbo() {
  run_step "libjpeg-turbo" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=RELEASE \
      -D ENABLE_STATIC=FALSE \
      -D CMAKE_INSTALL_DEFAULT_LIBDIR=lib \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/libjpeg-turbo-3.0.1 \
      ..
make
make install
CMD
}

build_libjxl() {
  run_step "libjxl" bash -e <<'CMD'
mkdir build
cd    build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_TESTING=OFF \
      -D BUILD_SHARED_LIBS=ON \
      -D JPEGXL_ENABLE_SKCMS=OFF \
      -D JPEGXL_ENABLE_SJPEG=OFF \
      -D JPEGXL_ENABLE_PLUGINS=ON \
      -D JPEGXL_INSTALL_JARDIR=/usr/share/java \
      -G Ninja ..
ninja
ninja install
gdk-pixbuf-query-loaders --update-cache
CMD
}

build_utfcpp() {
  run_step "utfcpp" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr ..
make install
CMD
}

build_asciidoctor() {
  run_step "Asciidoctor" bash -e <<'CMD'
gem build asciidoctor.gemspec
gem install asciidoctor-2.0.23.gem &&
install -vm644 man/asciidoctor.1 /usr/share/man/man1
CMD
}

build_bogofilter() {
  run_step "Bogofilter" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc/bogofilter \
            --with-database=sqlite3
make
make install
CMD
}

build_compface() {
  run_step "Compface" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_desktop_file_utils() {
  run_step "desktop-file-utils" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
install -vdm755 /usr/share/applications
update-desktop-database /usr/share/applications
CMD
}

build_dos2unix() {
  run_step "dos2unix" bash -e <<'CMD'
make
make install
CMD
}

build_glslc() {
  run_step "glslc" bash -e <<'CMD'
sed '/build-version/d'   -i glslc/CMakeLists.txt
sed '/third_party/d'     -i CMakeLists.txt
sed 's|SPIRV|glslang/&|' -i libshaderc_util/src/compiler.cc
echo '"2024.4"' > glslc/src/build-version.inc
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D SHADERC_SKIP_TESTS=ON     \
      -G Ninja ..
ninja
install -vm755 glslc/glslc /usr/bin
CMD
}

build_graphviz() {
  run_step "Graphviz" bash -e <<'CMD'
sed -i '/LIBPOSTFIX="64"/s/64//' configure.ac
./autogen.sh
./configure --prefix=/usr \
            --docdir=/usr/share/doc/graphviz-12.2.1
make
make install
CMD
}

build_pinentry() {
  run_step "pinentry" bash -e <<'CMD'
sed -i "/FLTK 1/s/3/4/" configure
sed -i '14462 s/1.3/1.4/' configure
./configure --prefix=/usr \
            --enable-pinentry-tty
make
make install
CMD
}

build_tree() {
  run_step "tree" bash -e <<'CMD'
make
make PREFIX=/usr MANDIR=/usr/share/man install
CMD
}

build_xdg_dbus_proxy() {
  run_step "xdg-dbus-proxy" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_gtk_doc() {
  run_step "GTK-Doc" bash -e <<'CMD'
mkdir -p build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_highlight() {
  run_step "Highlight" bash -e <<'CMD'
sed -i '/GZIP/s/^/#/' makefile
make
make doc_dir=/usr/share/doc/highlight-4.15/ gui
make doc_dir=/usr/share/doc/highlight-4.15/ install
make install-gui
CMD
}

build_ibus() {
  run_step "ibus" bash -e <<'CMD'
mkdir -p /usr/share/unicode/ucd
unzip -o ../UCD.zip -d /usr/share/unicode/ucd
sed -e 's@/desktop/ibus@/org/freedesktop/ibus@g' \
    -i data/dconf/org.freedesktop.ibus.gschema.xml
if ! [ -e /usr/bin/gtkdocize ]; then
  sed '/docs/d;/GTK_DOC/d' -i Makefile.am configure.ac
fi
SAVE_DIST_FILES=1 NOCONFIGURE=1 ./autogen.sh

PYTHON=python3 \
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-python2 \
            --disable-appindicator \
            --disable-emoji-dict \
            --disable-gtk2 \
            --disable-systemd-services
make
make install
gtk-query-immodules-3.0 --update-cache
CMD
}

build_imagemagick() {
  run_step "ImageMagick" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --enable-hdri \
            --with-modules \
            --with-perl \
            --disable-static
make
make DOCUMENTATION_PATH=/usr/share/doc/imagemagick-7.1.1 install
CMD
}

build_iso_codes() {
  run_step "ISO Codes" bash -e <<'CMD'
./configure --prefix=/usr
make
make install LN_S='ln -sfn'
CMD
}

build_lsof() {
  run_step "lsof" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make check
make install
CMD
}

build_screen() {
  run_step "Screen" bash -e <<'CMD'
./configure --prefix=/usr \
            --infodir=/usr/share/info \
            --mandir=/usr/share/man \
            --disable-pam \
            --enable-socket-dir=/run/screen \
            --with-pty-group=5 \
            --with-system_screenrc=/etc/screenrc
sed -i -e 's%/usr/local/etc/screenrc%/etc/screenrc%' {etc,doc}/*
make
make install
install -m 644 etc/etcscreenrc /etc/screenrc
CMD
}

build_shared_mime_info() {
  run_step "shared-mime-info" bash -e <<'CMD'
tar -xf ../xdgmime.tar.xz
make -C xdgmime
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -D update-mimedb=true ..
ninja
ninja install
CMD
}

build_sharutils() {
  run_step "Sharutils" bash -e <<'CMD'
sed -i 's/BUFSIZ/rw_base_size/' src/unshar.c
sed -i '/program_name/s/^/extern /' src/*opts.h
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/usr
make
make install
CMD
}

build_tidy_html5() {
  run_step "tidy-html5" bash -e <<'CMD'
cd build/cmake
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D BUILD_TAB2SPACE=ON \
      ../..
make
make install
rm -fv /usr/lib/libtidy.a
CMD
}

build_time_util() {
  run_step "Time" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_unixodbc() {
  run_step "unixODBC" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc/unixODBC
make
make install
find doc -name 'Makefile*' -delete
chmod 644 doc/{lst,ProgrammerManual/Tutorial}/*
install -v -m755 -d /usr/share/doc/unixODBC-2.3.12
cp -v -R doc/* /usr/share/doc/unixODBC-2.3.12
CMD
}

build_xdg_user_dirs() {
  run_step "Xdg-user-dirs" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-documentation
make
make install
CMD
}

# Chapter 12: System Utilities

build_7zip() {
  run_step "7zip" bash -e <<'CMD'
for i in Bundles/{Alone,Alone7z,Format7zF,SFXCon} UI/Console; do
    make -C CPP/7zip/$i -f ../../cmpl_gcc.mak
done
install -vDm755 CPP/7zip/Bundles/Alone{/b/g/7za,7z/b/g/7zr} \
                CPP/7zip/Bundles/Format7zF/b/g/7z.so        \
                CPP/7zip/UI/Console/b/g/7z                  \
                -t /usr/lib/7zip/
install -vm755 CPP/7zip/Bundles/SFXCon/b/g/7zCon \
               /usr/lib/7zip/7zCon.sfx
(for i in 7z 7za 7zr; do
    cat > /usr/bin/$i <<EOF
#!/bin/sh
exec /usr/lib/7zip/$i "$@"
EOF
    chmod 755 /usr/bin/$i || exit
done)
cp -rv DOC -T /usr/share/doc/7zip-24.09
CMD
}

build_accountsservice() {
  run_step "AccountsService" bash -e <<'CMD'
mv tests/dbusmock{,-tests}
sed -e '/accounts_service.py/s/dbusmock/dbusmock-tests/' \
    -e 's/assertEquals/assertEqual/'                      \
    -i tests/test-libaccountsservice.py
sed -i '/^SIMULATED_SYSTEM_LOCALE/s/en_IE.UTF-8/en_HK.iso88591/' tests/test-daemon.py
mkdir build &&
cd    build &&
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D admin_group=adm \
      -D elogind=true \
      -D systemdsystemunitdir=no
grep 'print_indent'     ../subprojects/mocklibc-1.0/src/netgroup.c \
     | sed 's/ {/;/' >> ../subprojects/mocklibc-1.0/src/netgroup.h &&
sed -i '1i#include <netdb.h>' \
    ../subprojects/mocklibc-1.0/src/netgroup.h
ninja
ninja install
cat > /etc/polkit-1/rules.d/40-adm.rules <<EOF
polkit.addAdminRule(function(action, subject) {
   return ["unix-group:adm"];
   });
EOF
CMD
}

build_acpid() {
  run_step "acpid" bash -e <<'CMD'
./configure --prefix=/usr \
            --docdir=/usr/share/doc/acpid-2.0.34
make
make install
install -v -m755 -d /etc/acpi/events
cp -r samples /usr/share/doc/acpid-2.0.34
CMD
}

build_at() {
  run_step "at" bash -e <<'CMD'
./configure --with-daemon_username=atd \
            --with-daemon_groupname=atd \
            --with-jobdir=/var/spool/atjobs \
            --with-atspool=/var/spool/atspool \
            SENDMAIL=/usr/sbin/sendmail
make -j1
make install docdir=/usr/share/doc/at-3.2.5 \
             atdocdir=/usr/share/doc/at-3.2.5
CMD
}

build_fcron() {
  run_step "Fcron" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --without-sendmail \
            --with-boot-install=no \
            --with-systemdsystemunitdir=no
make
make install
CMD
}

build_hdparm() {
  run_step "Hdparm" bash -e <<'CMD'
make
make binprefix=/usr install
CMD
}

build_logrotate() {
  run_step "Logrotate" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_mc() {
  run_step "MC" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --enable-charset
make
make install
CMD
}

build_usbutils() {
  run_step "usbutils" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release
ninja
ninja install
CMD
}

build_xdotool() {
  run_step "xdotool" bash -e <<'CMD'
make WITHOUT_RPATH_FIX=1
make PREFIX=/usr INSTALLMAN=/usr/share/man install
CMD
}

build_zip() {
  run_step "Zip" bash -e <<'CMD'
make -f unix/Makefile generic CC="gcc -std=gnu89"
make prefix=/usr MANDIR=/usr/share/man/man1 -f unix/Makefile install
CMD
}

build_dbus() {
  run_step "dbus" bash -e <<'CMD'
mkdir build &&
cd    build &&
meson setup --prefix=/usr \
            --buildtype=release \
            --wrap-mode=nofallback \
            -D systemd=disabled ..
ninja
ninja install
chown root:messagebus /usr/libexec/dbus-daemon-launch-helper
chmod 4750 /usr/libexec/dbus-daemon-launch-helper
dbus-uuidgen --ensure
ln -sfv /var/lib/dbus/machine-id /etc
CMD
}

build_pciutils() {
  run_step "pciutils" bash -e <<'CMD'
sed -r '/INSTALL/{/PCI_IDS|update-pciids /d; s/update-pciids.8//}' \
    -i Makefile
make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes
make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes install install-lib
chmod 755 /usr/lib/libpci.so
CMD
}

build_sysstat() {
  run_step "sysstat" bash -e <<'CMD'
sa_lib_dir=/usr/lib/sa \
sa_dir=/var/log/sa \
conf_dir=/etc/sysstat \
./configure --prefix=/usr --disable-file-attr
make
make install
CMD
}

build_bluez() {
  run_step "BlueZ" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --enable-library \
            --disable-manpages \
            --disable-systemd
make
make install
ln -svf ../libexec/bluetooth/bluetoothd /usr/sbin
install -v -dm755 /etc/bluetooth
install -v -m644 src/main.conf /etc/bluetooth/main.conf
install -v -dm755 /usr/share/doc/bluez-5.79
install -v -m644 doc/*.txt /usr/share/doc/bluez-5.79
install -m644 ./obexd/src/org.bluez.obex.service /usr/share/dbus-1/services
CMD
}

build_bubblewrap() {
  run_step "bubblewrap" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_colord() {
  run_step "Colord" bash -e <<'CMD'
patch -Np1 -i ../colord-1.4.7-upstream_fixes-1.patch
groupadd -fg 71 colord || true
useradd -c "Color Daemon Owner" -d /var/lib/colord -u 71 -g colord -s /bin/false colord || true
mkdir build && cd build
meson setup .. --prefix=/usr --buildtype=release \
      -D daemon_user=colord -D vapi=true -D systemd=false \
      -D libcolordcompat=true -D argyllcms_sensor=false \
      -D bash_completion=false -D docs=false -D man=false
ninja
ninja install
CMD
}

build_cpio() {
  run_step "cpio" bash -e <<'CMD'
./configure --prefix=/usr --enable-mt --with-rmt=/usr/libexec/rmt
make
makeinfo --html -o doc/html doc/cpio.texi
makeinfo --html --no-split -o doc/cpio.html doc/cpio.texi
makeinfo --plaintext -o doc/cpio.txt doc/cpio.texi
make -C doc pdf || true
make -C doc ps || true
make install
install -v -m755 -d /usr/share/doc/cpio-2.15/html
install -v -m644 doc/html/* /usr/share/doc/cpio-2.15/html
install -v -m644 doc/cpio.{html,txt} /usr/share/doc/cpio-2.15
CMD
}

build_cups_pk_helper() {
  run_step "cups-pk-helper" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr ..
ninja
ninja install
CMD
}

build_elogind() {
  run_step "elogind" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release \
      -D man=auto -D docdir=/usr/share/doc/elogind-255.17 \
      -D cgroup-controller=elogind -D dev-kvm-mode=0660 \
      -D dbuspolicydir=/etc/dbus-1/system.d
ninja
ninja install
ln -sfv libelogind.pc /usr/lib/pkgconfig/libsystemd.pc
ln -sfvn elogind /usr/include/systemd
CMD
}

build_lm_sensors() {
  run_step "lm-sensors" bash -e <<'CMD'
make PREFIX=/usr BUILD_STATIC_LIB=0 MANDIR=/usr/share/man EXLDFLAGS=
make PREFIX=/usr BUILD_STATIC_LIB=0 MANDIR=/usr/share/man install
install -v -m755 -d /usr/share/doc/lm-sensors-3-6-0
cp -rv README INSTALL doc/* /usr/share/doc/lm-sensors-3-6-0
CMD
}

build_modemmanager() {
  run_step "ModemManager" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static \
            --disable-maintainer-mode \
            --with-systemd-journal=no \
            --with-systemd-suspend-resume
make
make install
CMD
}

build_udisks() {
  run_step "UDisks" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static \
            --enable-available-modules
make
make install
CMD
}

build_upower() {
  run_step "UPower" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=/usr --buildtype=release \
      -D gtk-doc=false -D man=false \
      -D systemdsystemunitdir=no -D udevrulesdir=/usr/lib/udev/rules.d
ninja
ninja install
CMD
}

build_which() {
  run_step "Which" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_unrar() {
  run_step "UnRar" bash -e <<'CMD'
make -f makefile
install -v -m755 unrar /usr/bin
CMD
}

build_pax() {
  run_step "Pax" bash -e <<'CMD'
bash Build.sh
install -v pax /usr/bin
install -v -m644 pax.1 /usr/share/man/man1
CMD
}

build_autofs() {
  run_step "autofs" bash -e <<'CMD'
./configure --prefix=/usr \
            --with-mapdir=/etc/autofs \
            --with-libtirpc \
            --without-openldap \
            --mandir=/usr/share/man
make
make install
make install_samples
CMD
}

build_hwdata() {
  run_step "hwdata" bash -e <<'CMD'
./configure --prefix=/usr --disable-blacklist
make install
CMD
}

build_lsb_tools() {
  run_step "LSB-Tools" bash -e <<'CMD'
make
make install
rm /usr/sbin/lsbinstall
CMD
}

build_notification_daemon() {
  run_step "notification-daemon" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static
make
make install
CMD
}

build_pm_utils() {
  run_step "pm-utils" bash -e <<'CMD'
patch -Np1 -i ../pm-utils-1.4.1-bugfixes-1.patch
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/pm-utils-1.4.1
make
make install
CMD
}

build_power_profiles_daemon() {
  run_step "power-profiles-daemon" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D gtk_doc=false \
      -D tests=false \
      -D systemdsystemunitdir=/tmp
ninja
ninja install
rm -fv /tmp/power-profiles-daemon.service
install -vdm755 /var/lib/power-profiles-daemon
CMD
}

build_raptor() {
  run_step "Raptor" bash -e <<'CMD'
sed -i 's/20627/20627 && LIBXML_VERSION < 21100/' src/raptor_libxml.c
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_rasqal() {
  run_step "Rasqal" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_redland() {
  run_step "Redland" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_sg3_utils() {
  run_step "sg3_utils" bash -e <<'CMD'
./configure --prefix=/usr --disable-static
make
make install
CMD
}

build_sysmond() {
  run_step "sysmond" bash -e <<'CMD'
make
make install
make install-sysmond
CMD
}

build_sysmon3() {
  run_step "sysmon3" bash -e <<'CMD'
qmake sysmon3.pro
make
install -vm755 sysmon3 /usr/bin
CMD
}

build_ncftp() {
  run_step "NcFTP" bash -e <<'CMD'
sed -i 's/def HAVE_STDLIB_H/ 1/;s/extern select/extern int select/' configure
CC=/usr/bin/gcc ./configure --prefix=/usr --sysconfdir=/etc
make -C libncftp shared
make
make -C libncftp soinstall
make install
CMD
}

build_ntp() {
  run_step "ntp" bash -e <<'CMD'
groupadd -g 87 ntp || true
useradd -c "Network Time Protocol" -d /var/lib/ntp -u 87 -g ntp -s /bin/false ntp || true
sed -e 's;pthread_detach(NULL);pthread_detach(0);' -i configure sntp/configure
./configure --prefix=/usr --bindir=/usr/sbin --sysconfdir=/etc \
            --enable-linuxcaps --with-lineeditlibs=readline \
            --docdir=/usr/share/doc/ntp-4.2.8p18
make
make install
install -v -o ntp -g ntp -d /var/lib/ntp
CMD
}

build_rpcbind() {
  run_step "rpcbind" bash -e <<'CMD'
sed -i "/servname/s:rpcbind:sunrpc:" src/rpcbind.c
./configure --prefix=/usr --bindir=/usr/sbin --with-rpcuser=root \
            --enable-warmstarts --without-systemdsystemunitdir
make
make install
CMD
}

build_samba() {
  run_step "Samba" bash -e <<'CMD'
python3 -m venv --system-site-packages pyvenv
./pyvenv/bin/pip3 install cryptography pyasn1 iso8601
patch -Np1 -i ../samba-4.21.4-testsuite_linux_6_13-1.patch
PYTHON=$PWD/pyvenv/bin/python3 PATH=$PWD/pyvenv/bin:$PATH ./configure \
    --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
    --with-piddir=/run/samba --with-pammodulesdir=/usr/lib/security \
    --enable-fhs --without-ad-dc --without-systemd \
    --with-system-mitkrb5 --enable-selftest --disable-rpath-install
make
make install
install -v -m644 examples/smb.conf.default /etc/samba
sed -e 's;log file =.*;log file = /var/log/samba/%m.log;' \
    -e 's;path = /usr/spool/samba;path = /var/spool/samba;' \
    -i /etc/samba/smb.conf.default
mkdir -pv /etc/openldap/schema
install -v -m644 examples/LDAP/README /etc/openldap/schema/README.samba
install -v -m644 examples/LDAP/samba* /etc/openldap/schema
install -v -m755 examples/LDAP/{get*,ol*} /etc/openldap/schema
CMD
}

build_iw() {
  run_step "iw" bash -e <<'CMD'
sed -i '/INSTALL.*gz/s/.gz//' Makefile
make
make install
CMD
}

build_wireless_tools() {
  run_step "Wireless Tools" bash -e <<'CMD'
patch -Np1 -i ../wireless_tools-29-fix_iwlist_scanning-1.patch
make
make PREFIX=/usr INSTALL_MAN=/usr/share/man install
CMD
}

build_wpa_supplicant() {
  run_step "wpa_supplicant" bash -e <<'CMD'
cat > wpa_supplicant/.config <<EOF
CONFIG_BACKEND=file
CONFIG_CTRL_IFACE=y
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WEXT=y
CONFIG_DRIVER_WIRED=y
CONFIG_EAP_TLS=y
CONFIG_READLINE=y
CFLAGS += -I/usr/include/libnl3
EOF
make -C wpa_supplicant BINDIR=/usr/sbin LIBDIR=/usr/lib
install -v -m755 wpa_supplicant/wpa_{cli,passphrase,supplicant} /usr/sbin/
install -v -m644 wpa_supplicant/doc/docbook/wpa_supplicant.conf.5 /usr/share/man/man5/
install -v -m644 wpa_supplicant/doc/docbook/wpa_{cli,passphrase,supplicant}.8 /usr/share/man/man8/
install -v -m644 wpa_supplicant/dbus/fi.w1.wpa_supplicant1.service /usr/share/dbus-1/system-services/
install -v -d -m755 /etc/dbus-1/system.d
install -v -m644 wpa_supplicant/dbus/dbus-wpa_supplicant.conf /etc/dbus-1/system.d/wpa_supplicant.conf
CMD
}

# Chapter 13: Programming

build_cargo_c() {
  run_step "cargo-c" bash -e <<'CMD'
curl -LO https://github.com/lu-zero/cargo-c/releases/download/v0.10.11/Cargo.lock
[ ! -e /usr/include/libssh2.h ] || export LIBSSH2_SYS_USE_PKG_CONFIG=1
[ ! -e /usr/include/sqlite3.h ] || export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
cargo build --release
install -vm755 target/release/cargo-{capi,cbuild,cinstall,ctest} /usr/bin/
CMD
}

build_cbindgen() {
  run_step "Cbindgen" bash -e <<'CMD'
cargo build --release
install -Dm755 target/release/cbindgen /usr/bin/
CMD
}

build_doxygen() {
  run_step "Doxygen" bash -e <<'CMD'
mkdir -v build
cd       build
cmake -G "Unix Makefiles" \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=/usr \
      -D build_wizard=ON \
      -D force_qt=Qt6 \
      -W no-dev ..
make
make install
install -vm644 ../doc/*.1 /usr/share/man/man1
CMD
}

build_git() {
  run_step "Git" bash -e <<'CMD'
./configure --prefix=/usr \
            --with-gitconfig=/etc/gitconfig \
            --with-python=python3
make
make perllibdir=/usr/lib/perl5/5.40/site_perl install
make install-man
make htmldir=/usr/share/doc/git-2.48.1 install-html
CMD
}

build_python3() {
  run_step "Python-3" bash -e <<'CMD'
./configure --prefix=/usr \
            --enable-shared \
            --with-system-expat \
            --enable-optimizations
make
make install
CMD
}

build_python3_11() {
  run_step "Python-3.11" bash -e <<'CMD'
CXX="/usr/bin/g++" ./configure \
            --prefix=/opt/python3.11 \
            --disable-shared \
            --with-system-expat
make
make install
CMD
}

build_cssselect() {
  run_step "cssselect" bash -e <<'CMD'
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links dist --no-user cssselect
CMD
}

build_cython() {
  run_step "Cython" bash -e <<'CMD'
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links dist --no-user Cython
CMD
}

build_docutils() {
  run_step "docutils" bash -e <<'CMD'
for f in /usr/bin/rst*.py; do rm -fv /usr/bin/$(basename $f .py); done
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links dist --no-user docutils
CMD
}

build_cmake() {
  run_step "CMake" bash -e <<'CMD'
sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake
./bootstrap --prefix=/usr \
            --system-libs \
            --mandir=/share/man \
            --no-system-jsoncpp \
            --no-system-cppdap \
            --no-system-librhash \
            --docdir=/share/doc/cmake-3.31.5
make
make install
CMD
}

build_lua() {
  run_step "Lua" bash -e <<'CMD'
cat > lua.pc << "EOF"
V=5.4
R=5.4.7

prefix=/usr
INSTALL_BIN=${prefix}/bin
INSTALL_INC=${prefix}/include
INSTALL_LIB=${prefix}/lib
INSTALL_MAN=${prefix}/share/man/man1
INSTALL_LMOD=${prefix}/share/lua/${V}
INSTALL_CMOD=${prefix}/lib/lua/${V}
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Lua
Description: An Extensible Extension Language
Version: ${R}
Requires:
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
EOF
patch -Np1 -i ../lua-5.4.7-shared_library-1.patch
make linux
make INSTALL_TOP=/usr \
     INSTALL_DATA="cp -d" \
     INSTALL_MAN=/usr/share/man/man1 \
     TO_LIB="liblua.so liblua.so.5.4 liblua.so.5.4.7" install
mkdir -pv /usr/share/doc/lua-5.4.7
cp -v doc/*.{html,css,gif,png} /usr/share/doc/lua-5.4.7
install -v -m644 -D lua.pc /usr/lib/pkgconfig/lua.pc
CMD
}

build_mercurial() {
  run_step "Mercurial" bash -e <<'CMD'
make build
make doc
sed -i '138,142d' Makefile
make PREFIX=/usr install-bin
make PREFIX=/usr install-doc
install -v -d -m755 /etc/mercurial
cat > /etc/mercurial/hgrc << "EOF"
[web]
cacerts = /etc/pki/tls/certs/ca-bundle.crt
EOF
CMD
}

build_nasm() {
  run_step "NASM" bash -e <<'CMD'
tar -xf ../nasm-2.16.03-xdoc.tar.xz --strip-components=1
./configure --prefix=/usr
make
make install
install -m755 -d         /usr/share/doc/nasm-2.16.03/html
cp -v doc/html/*.html    /usr/share/doc/nasm-2.16.03/html
cp -v doc/*.{txt,ps,pdf} /usr/share/doc/nasm-2.16.03
CMD
}

build_php() {
  run_step "PHP" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --datadir=/usr/share/php \
            --mandir=/usr/share/man \
            --without-pear \
            --enable-fpm \
            --with-fpm-user=apache \
            --with-fpm-group=apache \
            --with-config-file-path=/etc \
            --with-zlib \
            --enable-bcmath \
            --with-bz2 \
            --enable-calendar \
            --enable-dba=shared \
            --with-gdbm \
            --with-gmp \
            --enable-ftp \
            --with-gettext \
            --enable-mbstring \
            --disable-mbregex \
            --with-readline
make
make install
install -v -m644 php.ini-production /etc/php.ini
install -v -m755 -d /usr/share/doc/php-8.4.4
install -v -m644 CODING_STANDARDS* EXTENSIONS NEWS README* UPGRADING* \
               /usr/share/doc/php-8.4.4
CMD
}

build_clisp() {
  run_step "Clisp" bash -e <<'CMD'
case $(uname -m) in
    i?86) export CFLAGS="${CFLAGS:--O2 -g} -falign-functions=4" ;;
esac
sed -i -e '/socket/d' -e '/"streams"/d' tests/tests.lisp
patch -Np1 -i ../clisp-2.49-readline7_fixes-1.patch
mkdir build
cd build
../configure --srcdir=../ \
             --prefix=/usr \
             --docdir=/usr/share/doc/clisp-2.49 \
             --with-libsigsegv-prefix=/usr
ulimit -S -s 16384
make -j1
make install
CMD
}

build_gcc() {
  run_step "GCC" bash -e <<'CMD'
case $(uname -m) in
  x86_64) sed -i.orig '/m64=/s/lib64/lib/' gcc/config/i386/t-linux64 ;;
esac
mkdir build
cd build
../configure \
    --prefix=/usr \
    --disable-multilib \
    --with-system-zlib \
    --enable-default-pie \
    --enable-default-ssp \
    --enable-host-pie \
    --disable-fixincludes \
    --enable-languages=c,c++,fortran,go,objc,obj-c++,m2
make
make install
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
chown -v -R root:root /usr/lib/gcc/*linux-gnu/14.2.0/include{,-fixed}
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/14.2.0/liblto_plugin.so /usr/lib/bfd-plugins/
CMD
}

build_gdb() {
  run_step "GDB" bash -e <<'CMD'
mkdir build
cd build
../configure --prefix=/usr \
             --with-system-readline \
             --with-python=/usr/bin/python3
make
make -C gdb install
make -C gdbserver install
CMD
}

# Chapter 14: Connecting to a Network

build_dhcpcd() {
  run_step "dhcpcd" bash -e <<'CMD'
install -v -m700 -d /var/lib/dhcpcd
groupadd -g 52 dhcpcd
useradd -c 'dhcpcd PrivSep' -d /var/lib/dhcpcd -g dhcpcd -s /bin/false -u 52 dhcpcd
chown -v dhcpcd:dhcpcd /var/lib/dhcpcd
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --libexecdir=/usr/lib/dhcpcd \
            --dbdir=/var/lib/dhcpcd \
            --runstatedir=/run \
            --privsepuser=dhcpcd
make
make install
make install-service-dhcpcd
CMD
}

# Chapter 15: Networking Programs

build_bridge_utils() {
  run_step "bridge-utils" bash -e <<'CMD'
autoconf
./configure --prefix=/usr
make
make install
make install-service-bridge
CMD
}

build_cifs_utils() {
  run_step "cifs-utils" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-pam \
            --disable-systemd
make
make install
CMD
}

build_nfs_utils() {
  run_step "NFS-Utils" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --sbindir=/usr/sbin \
            --disable-nfsv4 \
            --disable-gss \
            LIBS="-lsqlite3 -levent_core"
make
make install
chmod u+w,go+r /usr/sbin/mount.nfs
chown nobody:nogroup /var/lib/nfs
CMD
}

build_rsync() {
  run_step "rsync" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-xxhash \
            --without-included-zlib
make
make install
CMD
}

build_wget() {
  run_step "Wget" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --with-ssl=openssl
make
make install
CMD
}

build_net_tools() {
  run_step "net-tools" bash -e <<'CMD'
export BINDIR='/usr/bin' SBINDIR='/usr/bin'
yes "" | make -j1
make DESTDIR=$PWD/install -j1 install
rm install/usr/bin/{nis,yp}domainname
rm install/usr/bin/{hostname,dnsdomainname,domainname,ifconfig}
rm -r install/usr/share/man/man1
rm install/usr/share/man/man8/ifconfig.8
unset BINDIR SBINDIR
chown -R root:root install
cp -a install/* /
CMD
}

build_avahi() {
  run_step "avahi" bash -e <<'CMD'
groupadd -fg 84 avahi || true
useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi || true
groupadd -fg 86 netdev || true
patch -Np1 -i ../avahi-0.8-ipv6_race_condition_fix-1.patch
sed -i "426a if (events & AVAHI_WATCH_HUP) {\nclient_free(c);\nreturn;\n}" avahi-daemon/simple-protocol.c
./configure --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --disable-static \
    --disable-libevent \
    --disable-mono \
    --disable-monodoc \
    --disable-python \
    --disable-qt3 \
    --disable-qt4 \
    --disable-qt5 \
    --enable-core-docs \
    --with-distro=none \
    --with-systemdsystemunitdir=no \
    --with-dbus-system-address='unix:path=/run/dbus/system_bus_socket'
make
make install
make install-avahi
CMD
}

build_bind_utils() {
  run_step "BIND Utilities" bash -e <<'CMD'
./configure --prefix=/usr
make -C lib/isc
make -C lib/dns
make -C lib/ns
make -C lib/isccfg
make -C lib/isccc
make -C bin/dig
make -C bin/nsupdate
make -C bin/rndc
make -C doc
make -C lib/isc install
make -C lib/dns install
make -C lib/ns install
make -C lib/isccfg install
make -C lib/isccc install
make -C bin/dig install
make -C bin/nsupdate install
make -C bin/rndc install
cp -v doc/man/{dig.1,host.1,nslookup.1,nsupdate.1} /usr/share/man/man1
cp -v doc/man/rndc.8 /usr/share/man/man8
CMD
}

build_networkmanager() {
  run_step "NetworkManager" bash -e <<'CMD'
grep -rl '^#!.*python$' | xargs sed -i '1s/python/&3/'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D libaudit=no \
      -D nmtui=true \
      -D ovs=false \
      -D ppp=false \
      -D selinux=false \
      -D session_tracking=elogind \
      -D modem_manager=false \
      -D systemdsystemunitdir=no \
      -D systemd_journal=false \
      -D qt=false
ninja
ninja install
mv -v /usr/share/doc/NetworkManager{,-1.50.0}
for file in $(echo ../man/*.[1578]); do
  section=${file##*.}
  install -vdm 755 /usr/share/man/man$section
  install -vm 644 $file /usr/share/man/man$section/
done
cp -Rv ../docs/{api,libnm} /usr/share/doc/NetworkManager-1.50.0
cat >> /etc/NetworkManager/NetworkManager.conf <<EOF
[main]
plugins=keyfile
EOF
cat > /etc/NetworkManager/conf.d/polkit.conf <<EOF
[main]
auth-polkit=true
EOF
CMD
}

build_network_manager_applet() {
  run_step "network-manager-applet" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D appindicator=no \
      -D selinux=false \
      -D team=false
ninja
ninja install
CMD
}

build_nmap() {
  run_step "Nmap" bash -e <<'CMD'
pip3 install build
./configure --prefix=/usr
make
make install
CMD
}

build_traceroute() {
  run_step "Traceroute" bash -e <<'CMD'
make
make prefix=/usr install
ln -sv -f traceroute /usr/bin/traceroute6
ln -sv -f traceroute.8 /usr/share/man/man8/traceroute6.8
rm -fv /usr/share/man/man1/traceroute.1
CMD
}

build_whois() {
  run_step "Whois" bash -e <<'CMD'
make
make prefix=/usr install-whois
make prefix=/usr install-mkpasswd
make prefix=/usr install-pos
CMD
}

build_wireshark() {
  run_step "Wireshark" bash -e <<'CMD'
groupadd -g 62 wireshark || true
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/wireshark-4.4.5 \
      -G Ninja \
      ..
ninja
ninja install
install -v -m755 -d /usr/share/doc/wireshark-4.4.5
install -v -m644 ../README.linux ../doc/README.* ../doc/randpkt.txt \
                /usr/share/doc/wireshark-4.4.5
pushd /usr/share/doc/wireshark-4.4.5
  for FILENAME in ../../wireshark/*.html; do
    ln -s -v -f $FILENAME .
  done
popd
unset FILENAME
chown -v root:wireshark /usr/bin/tshark
chmod -v 6550 /usr/bin/tshark
CMD
}

# Additional packages

build_gpm() {
  run_step "GPM" bash -e <<'CMD'
patch -Np1 -i ../gpm-1.20.7-consolidated-1.patch
./autogen.sh
./configure --prefix=/usr --sysconfdir=/etc ac_cv_path_emacs=no
make
make install
install-info --dir-file=/usr/share/info/dir /usr/share/info/gpm.info
rm -fv /usr/lib/libgpm.a
ln -sfv libgpm.so.2.1.0 /usr/lib/libgpm.so
install -v -m644 conf/gpm-root.conf /etc
install -v -m755 -d /usr/share/doc/gpm-1.20.7/support
install -v -m644 doc/support/* /usr/share/doc/gpm-1.20.7/support
install -v -m644 doc/{FAQ,HACK_GPM,README*} /usr/share/doc/gpm-1.20.7
CMD
}

build_blocaled() {
  run_step "blocaled" bash -e <<'CMD'
./configure --prefix=/usr --sysconfdir=/etc
make
make install
CMD
}

build_gc() {
  run_step "GC" bash -e <<'CMD'
./configure --prefix=/usr \
    --enable-cplusplus \
    --disable-static \
    --docdir=/usr/share/doc/gc-8.2.8
make
make install
install -v -m644 doc/gc.man /usr/share/man/man3/gc_malloc.3
CMD
}

build_dtc() {
  run_step "dtc" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -D python=disabled ..
ninja
ninja install
rm /usr/lib/libfdt.a
cp -R ../Documentation -T /usr/share/doc/dtc-1.7.2
CMD
}

build_patchelf() {
  run_step "patchelf" bash -e <<'CMD'
./configure --prefix=/usr --docdir=/usr/share/doc/patchelf-0.18.0
make
make install
CMD
}

build_guile() {
  run_step "Guile" bash -e <<'CMD'
./configure --prefix=/usr \
    --disable-static \
    --docdir=/usr/share/doc/guile-3.0.10
make
make html
makeinfo --plaintext -o doc/r5rs/r5rs.txt doc/r5rs/r5rs.texi
makeinfo --plaintext -o doc/ref/guile.txt doc/ref/guile.texi
make install
make install-html
mkdir -p /usr/share/gdb/auto-load/usr/lib
mv /usr/lib/libguile-*-gdb.scm /usr/share/gdb/auto-load/usr/lib
mv /usr/share/doc/guile-3.0.10/{guile.html,ref}
mv /usr/share/doc/guile-3.0.10/r5rs{.html,}
find examples -name "Makefile*" -delete
cp -vR examples /usr/share/doc/guile-3.0.10
for DIRNAME in r5rs ref; do
  install -v -m644 doc/${DIRNAME}/*.txt /usr/share/doc/guile-3.0.10/${DIRNAME}
done
unset DIRNAME
CMD
}

build_luajit() {
  run_step "luajit" bash -e <<'CMD'
make PREFIX=/usr amalg
make PREFIX=/usr install
rm -v /usr/lib/libluajit-5.1.a
CMD
}

build_valgrind() {
  run_step "valgrind" bash -e <<'CMD'
sed -i 's|/doc/valgrind||' docs/Makefile.in
./configure --prefix=/usr --datadir=/usr/share/doc/valgrind-3.24.0
make
make install
CMD
}

build_llvm() {
  run_step "LLVM" bash -e <<'CMD'
sed 's/utility/tool/' -i utils/FileCheck/CMakeLists.txt
mkdir -v build
cd build
CC=gcc CXX=g++ \
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D LLVM_ENABLE_FFI=ON \
      -D CMAKE_BUILD_TYPE=Release \
      -D LLVM_BUILD_LLVM_DYLIB=ON \
      -D LLVM_LINK_LLVM_DYLIB=ON \
      -D LLVM_ENABLE_RTTI=ON \
      -D LLVM_TARGETS_TO_BUILD="host;AMDGPU" \
      -D LLVM_BINUTILS_INCDIR=/usr/include \
      -D LLVM_INCLUDE_BENCHMARKS=OFF \
      -D CLANG_DEFAULT_PIE_ON_LINUX=ON \
      -D CLANG_CONFIG_FILE_SYSTEM_DIR=/etc/clang \
      -W no-dev -G Ninja ..
ninja
ninja install
CMD
}

build_openjdk() {
  run_step "OpenJDK" bash -e <<'CMD'
tar -xf ../jtreg-7.3.1+1.tar.gz
unset JAVA_HOME CLASSPATH MAKEFLAGS
bash configure --enable-unlimited-crypto \
               --disable-warnings-as-errors \
               --with-stdc++lib=dynamic \
               --with-giflib=system \
               --with-harfbuzz=system \
               --with-jtreg=$PWD/jtreg \
               --with-lcms=system \
               --with-libjpeg=system \
               --with-libpng=system \
               --with-zlib=system \
               --with-version-build="7" \
               --with-version-pre="" \
               --with-version-opt="" \
               --with-jobs=$(nproc) \
               --with-cacerts-file=/etc/pki/tls/java/cacerts
make images
install -vdm755 /opt/jdk-23.0.2+7
cp -Rv build/*/images/jdk/* /opt/jdk-23.0.2+7
chown -R root:root /opt/jdk-23.0.2+7
for s in 16 24 32 48; do
  install -vDm644 src/java.desktop/unix/classes/sun/awt/X11/java-icon${s}.png \
                  /usr/share/icons/hicolor/${s}x${s}/apps/java.png
done
ln -v -nsf jdk-23.0.2+7 /opt/jdk
mkdir -pv /usr/share/applications
cat > /usr/share/applications/openjdk-java.desktop <<EOF
[Desktop Entry]
Name=OpenJDK Java 23.0.2 Runtime
Comment=OpenJDK Java 23.0.2 Runtime
Exec=/opt/jdk/bin/java -jar
Terminal=false
Type=Application
Icon=java
MimeType=application/x-java-archive;application/java-archive;application/x-jar;
NoDisplay=true
EOF
cat > /usr/share/applications/openjdk-jconsole.desktop <<EOF
[Desktop Entry]
Name=OpenJDK Java 23.0.2 Console
Comment=OpenJDK Java 23.0.2 Console
Keywords=java;console;monitoring
Exec=/opt/jdk/bin/jconsole
Terminal=false
Type=Application
Icon=java
Categories=Application;System;
EOF
CMD
}

build_java_bin() {
  run_step "Java" bash -e <<'CMD'
install -vdm755 /opt/OpenJDK-23.0.2-bin
mv -v * /opt/OpenJDK-23.0.2-bin
chown -R root:root /opt/OpenJDK-23.0.2-bin
ln -sfn OpenJDK-23.0.2-bin /opt/jdk
CMD
}

build_vala() {
  run_step "Vala" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_yasm() {
  run_step "yasm" bash -e <<'CMD'
sed -i 's#) ytasm.*#)#' Makefile.in
./configure --prefix=/usr
make
make install
CMD
}

build_ruby() {
  run_step "Ruby" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-rpath \
            --enable-shared \
            --without-valgrind \
            --without-baseruby \
            ac_cv_func_qsort_r=no \
            --docdir=/usr/share/doc/ruby-3.4.2
make
make install
CMD
}

build_rustc() {
  run_step "Rustc" bash -e <<'CMD'
mkdir -pv /opt/rustc-1.85.0
ln -svfn rustc-1.85.0 /opt/rustc
cat > config.toml <<'EOF'
[build]
extended = true
tools = ["cargo", "clippy", "rustdoc", "rustfmt"]
[install]
prefix = "/opt/rustc-1.85.0"
docdir = "share/doc/rustc-1.85.0"
EOF
sed '/MirOpt/d' -i src/bootstrap/src/core/builder/mod.rs
[ ! -e /usr/include/libssh2.h ] || export LIBSSH2_SYS_USE_PKG_CONFIG=1
[ ! -e /usr/include/sqlite3.h ] || export LIBSQLITE3_SYS_USE_PKG_CONFIG=1
./x.py build
./x.py install rustc std
./x.py install --stage=1 cargo clippy rustfmt
unset LIB{SSH2,SQLITE3}_SYS_USE_PKG_CONFIG
CMD
}

build_rust_bindgen() {
  run_step "rust-bindgen" bash -e <<'CMD'
cargo build --release
install -Dm755 target/release/bindgen /usr/bin/
bindgen --generate-shell-completions bash > /usr/share/bash-completion/completions/bindgen
bindgen --generate-shell-completions zsh > /usr/share/zsh/site-functions/_bindgen
CMD
}

build_scons() {
  run_step "SCons" bash -e <<'CMD'
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links dist --no-user SCons
install -v -m664 *.1 /usr/share/man/man1
CMD
}

build_slang() {
  run_step "slang" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --with-readline=gnu
make -j1 RPATH=
make install_doc_dir=/usr/share/doc/slang-2.3.3 \
     SLSH_DOC_DIR=/usr/share/doc/slang-2.3.3/slsh \
     RPATH= install
CMD
}

build_subversion() {
  run_step "Subversion" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --with-apache-libexecdir \
            --with-utf8proc=internal
make
make install
install -v -m755 -d /usr/share/doc/subversion-1.14.5
cp -v -R doc/* /usr/share/doc/subversion-1.14.5
CMD
}

build_swig() {
  run_step "SWIG" bash -e <<'CMD'
./configure --prefix=/usr \
            --without-javascript \
            --without-maximum-compile-warnings
make
make install
cp -v -R Doc -T /usr/share/doc/swig-4.3.0
CMD
}

build_tk() {
  run_step "Tk" bash -e <<'CMD'
cd unix
./configure --prefix=/usr \
            --mandir=/usr/share/man \
            $([ $(uname -m) = x86_64 ] && echo --enable-64bit)
make
sed -e "s@^\(TK_SRC_DIR='\).*@\1/usr/include@" \
    -e "/TK_B/s@='\(-L\)?[^']*unix@='\1/usr/lib@" \
    -i tkConfig.sh
make install
make install-private-headers
ln -sf wish8.6 /usr/bin/wish
chmod 755 /usr/lib/libtk8.6.so
CMD
}

build_curl() {
  run_step "curl" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --with-openssl \
            --with-ca-path=/etc/ssl/certs
make
make install
rm -rf docs/examples/.deps
find docs \( -name Makefile\* -o -name \*.1 -o -name \*.3 -o -name CMakeLists.txt \) -delete
cp -v -R docs -T /usr/share/doc/curl-8.12.1
CMD
}

build_libevent() {
  run_step "libevent" bash -e <<'CMD'
sed -i 's/python/&3/' event_rpcgen.py
./configure --prefix=/usr --disable-static
make
doxygen Doxyfile
make install
install -v -m755 -d /usr/share/doc/libevent-2.1.12/api
cp -v -R doxygen/html/* /usr/share/doc/libevent-2.1.12/api
CMD
}

build_libpcap() {
  run_step "libpcap" bash -e <<'CMD'
./configure --prefix=/usr
make
sed -i '/INSTALL_DATA.*libpcap.a\|RANLIB.*libpcap.a/ s/^/#/' Makefile
make install
CMD
}

build_nghttp2() {
  run_step "nghttp2" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static \
            --enable-lib-only \
            --docdir=/usr/share/doc/nghttp2-1.64.0
make
make install
CMD
}

build_libsoup() {
  run_step "libsoup" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D vapi=enabled \
            -D gssapi=disabled \
            -D sysprof=disabled \
            ..
ninja
ninja install
CMD
}

build_libsoup3() {
  run_step "libsoup3" bash -e <<'CMD'
sed 's/apiversion/soup_version/' -i docs/reference/meson.build
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            --wrap-mode=nofallback \
            ..
ninja
ninja install
CMD
}

build_kdsoap() {
  run_step "kdsoap" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D KDSoap_QT6=ON \
      -D CMAKE_INSTALL_DOCDIR=/usr/share/doc/kdsoap-2.2.0 \
      ..
make
make install
CMD
}

build_kdsoap_ws_discovery_client() {
  run_step "kdsoap-ws-discovery-client" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_SKIP_INSTALL_RPATH=ON \
      -D QT_MAJOR_VERSION=6 \
      -W no-dev ..
make
make install
mv -v /usr/share/doc/KDSoapWSDiscoveryClient{,-0.4.0}
CMD
}

build_libnl() {
  run_step "libnl" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static
make
make install
mkdir -vp /usr/share/doc/libnl-3.11.0
tar -xf ../libnl-doc-3.11.0.tar.gz --strip-components=1 --no-same-owner \
    -C /usr/share/doc/libnl-3.11.0
CMD
}

build_libnsl() {
  run_step "libnsl" bash -e <<'CMD'
./configure --sysconfdir=/etc --disable-static
make
make install
CMD
}

build_libtirpc() {
  run_step "libtirpc" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static \
            --disable-gssapi
make
make install
CMD
}

build_links() {
  run_step "Links" bash -e <<'CMD'
./configure --prefix=/usr --mandir=/usr/share/man
make
make install
install -v -d -m755 /usr/share/doc/links-2.30
install -v -m644 doc/links_cal/* KEYS BRAILLE_HOWTO /usr/share/doc/links-2.30
CMD
}

build_lynx() {
  run_step "Lynx" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc/lynx \
            --with-zlib \
            --with-bzlib \
            --with-ssl \
            --with-screen=ncursesw \
            --enable-locale-charset \
            --datadir=/usr/share/doc/lynx-2.9.2
make
make install-full
chgrp -v -R root /usr/share/doc/lynx-2.9.2/lynx_doc
sed -e '/#LOCALE/     a LOCALE_CHARSET:TRUE'     \
    -i /etc/lynx/lynx.cfg
sed -e '/#DEFAULT_ED/ a DEFAULT_EDITOR:vi'       \
    -i /etc/lynx/lynx.cfg
sed -e '/#PERSIST/    a PERSISTENT_COOKIES:TRUE' \
    -i /etc/lynx/lynx.cfg
CMD
}

build_mutt() {
  run_step "Mutt" bash -e <<'CMD'
groupadd -g 34 mail || true
chgrp -v mail /var/mail
sed  -e 's/ -with_backspaces//' \
     -e 's/elinks/links/'       \
     -e 's/-no-numbering -no-references//' \
     -i doc/Makefile.in
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --with-docdir=/usr/share/doc/mutt-2.2.14 \
            --with-ssl \
            --enable-external-dotlock \
            --enable-pop \
            --enable-imap \
            --enable-hcache \
            --enable-sidebar
make
make install
chown root:mail /usr/bin/mutt_dotlock
chmod -v 2755 /usr/bin/mutt_dotlock
cat /usr/share/doc/mutt-2.2.14/samples/gpg.rc >> ~/.muttrc
CMD
}

build_procmail() {
  run_step "Procmail" bash -e <<'CMD'
patch -Np1 -i ../procmail-3.24-consolidated_fixes-1.patch
make LOCKINGTEST=/tmp MANDIR=/usr/share/man install
make install-suid
CMD
}

build_unifdef() {
  run_step "unifdef" bash -e <<'CMD'
make
make prefix=/usr install
CMD
}

build_apache_ant() {
  run_step "apache-ant" bash -e <<'CMD'
./bootstrap.sh
bootstrap/bin/ant -f fetch.xml -Ddest=optional
./build.sh -Ddist.dir=$PWD/ant-1.10.15 dist
cp -rv ant-1.10.15 /opt/
chown -R root:root /opt/ant-1.10.15

  ln -sfv ant-1.10.15 /opt/ant
CMD
}

build_c_ares() {
  run_step "c-ares" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr ..
make
make install
CMD
}

build_geoclue() {
  run_step "GeoClue" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D gtk-doc=false
ninja
ninja install
CMD
}

build_glib_networking() {
  run_step "glib-networking" bash -e <<'CMD'
mkdir build
cd build
meson setup \
   --prefix=/usr \
   --buildtype=release \
   -D libproxy=disabled ..
ninja
ninja install
CMD
}

build_ldns() {
  run_step "ldns" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --disable-static \
            --with-drill
make
make install
install -v -m755 -d /usr/share/doc/ldns-1.8.4
install -v -m644 doc/html/* /usr/share/doc/ldns-1.8.4
CMD
}

build_libmnl() {
  run_step "libmnl" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_libndp() {
  run_step "libndp" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --disable-static
make
make install
CMD
}

build_libnma() {
  run_step "libnma" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D gtk_doc=false \
      -D libnma_gtk4=true \
      -D mobile_broadband_provider_info=false
ninja
ninja install
CMD
}

build_libpsl() {
  run_step "libpsl" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_libslirp() {
  run_step "libslirp" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
CMD
}

build_neon() {
  run_step "neon" bash -e <<'CMD'
./configure --prefix=/usr \
            --with-ssl \
            --enable-shared \
            --disable-static
make
make install
CMD
}

build_rpcsvc_proto() {
  run_step "rpcsvc-proto" bash -e <<'CMD'
./configure --sysconfdir=/etc
make
make install
CMD
}

build_serf() {
  run_step "Serf" bash -e <<'CMD'
sed -i "/Append/s:RPATH=libdir,::" SConstruct
sed -i "/Default/s:lib_static,::" SConstruct
sed -i "/Alias/s:install_static,::" SConstruct
scons PREFIX=/usr
scons PREFIX=/usr install
CMD
}

build_uhttpmock() {
  run_step "uhttpmock" bash -e <<'CMD'
mkdir build
cd build
meson setup .. \
      --prefix=/usr \
      --buildtype=release \
      -D gtk_doc=false
ninja
ninja install
CMD
}

build_fetchmail() {
  run_step "Fetchmail" bash -e <<'CMD'
useradd -c "Fetchmail User" -d /dev/null -g nogroup -s /bin/false -u 38 fetchmail || true
./configure --prefix=/usr
make
make install
chown -v fetchmail:nogroup /usr/bin/fetchmail
CMD
}

build_mailx() {
  run_step "mailx" bash -e <<'CMD'
patch -Np1 -i ../heirloom-mailx-12.5-fixes-1.patch
sed 's@<openssl@<openssl-1.0/openssl@' -i openssl.c fio.c makeconfig
make -j1 LDFLAGS+="-L /usr/lib/openssl/" SENDMAIL=/usr/sbin/sendmail
make PREFIX=/usr UCBINSTALL=/usr/bin/install install
ln -sf mailx /usr/bin/mail
ln -sf mailx /usr/bin/nail
install -d -m755 /usr/share/doc/heirloom-mailx-12.5
install -m644 README /usr/share/doc/heirloom-mailx-12.5
CMD
}

build_apache() {
  run_step "Apache" bash -e <<'CMD'
groupadd -g 25 apache || true
useradd -c "Apache Server" -d /srv/www -g apache -s /bin/false -u 25 apache || true
sed -e '/dir.*CFG_PREFIX/s@^@#@' -i support/apxs.in
sed -e '/HTTPD_ROOT/s@/usr/local/apache2@/srv/www@' \
    -e '/SERVER_CONFIG_FILE/s@apache2@httpd@' -i docs/conf/httpd.conf.in
sed -e '/encoding.h/a #include <apr_escape.h>' -i server/util.c
./configure --enable-authnz-fcgi \
            --enable-layout=BLFS \
            --enable-mods-shared="all cgi" \
            --enable-mpms-shared=all \
            --enable-suexec=shared \
            --with-apr=/usr/bin/apr-1-config \
            --with-apr-util=/usr/bin/apu-1-config \
            --with-suexec-bin=/usr/lib/httpd/suexec \
            --with-suexec-caller=apache \
            --with-suexec-docroot=/srv/www \
            --with-suexec-logfile=/var/log/httpd/suexec.log \
            --with-suexec-uidmin=100 \
            --with-suexec-userdir=public_html
make
make install
mv -v /usr/sbin/suexec /usr/lib/httpd/suexec
chgrp apache /usr/lib/httpd/suexec
chmod 4754 /usr/lib/httpd/suexec
chown -R apache:apache /srv/www
CMD
}

build_bind() {
  run_step "BIND" bash -e <<'CMD'
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --mandir=/usr/share/man \
            --disable-static \
            --with-python=python3
make
make install
CMD
}

build_kea() {
  run_step "Kea" bash -e <<'CMD'
patch -Np1 -i ../kea-2.6.1-fix_boost_1_87-1.patch
./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --enable-shell \
            --with-openssl \
            --disable-static \
            --docdir=/usr/share/doc/kea-2.6.1
make
make -j1 install
CMD
}

build_proftpd() {
  run_step "ProFTPD" bash -e <<'CMD'
groupadd -g 46 proftpd || true
useradd -c proftpd -d /srv/ftp -g proftpd -s /bin/false -u 46 proftpd || true
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/run
make
make install
install -d -m755 /usr/share/doc/proftpd-1.3.8b
cp -Rv doc/* /usr/share/doc/proftpd-1.3.8b
ln -sfv ant-1.10.15 /opt/ant
CMD
}
# Chapter 24: X Window System

build_util_macros() {
  run_step "util-macros" bash -e <<'CMD'
./configure $XORG_CONFIG
make install
CMD
}

build_xorgproto() {
  run_step "xorgproto" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=$XORG_PREFIX ..
ninja
ninja install
mv -v $XORG_PREFIX/share/doc/xorgproto{,-2024.1}
CMD
}

build_libxau() {
  run_step "libXau" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make check
make install
CMD
}

build_libxdmcp() {
  run_step "libXdmcp" bash -e <<'CMD'
./configure $XORG_CONFIG \
            --docdir=/usr/share/doc/libXdmcp-1.1.5
make
make check
make install
CMD
}

build_xcb_proto() {
  run_step "xcb-proto" bash -e <<'CMD'
PYTHON=python3 ./configure $XORG_CONFIG
make check
make install
rm -f $XORG_PREFIX/lib/pkgconfig/xcb-proto.pc
CMD
}

build_libxcb() {
  run_step "libxcb" bash -e <<'CMD'
./configure $XORG_CONFIG      \
            --without-doxygen \
            --docdir='${datadir}'/doc/libxcb-1.17.0
LC_ALL=en_US.UTF-8 make
make check
make install
CMD
}

build_xorg_libraries() {
  run_step "Xorg-Libraries" bash -e <<'CMD'
cat > /tmp/lib-7.md5 << "XEOF"
6ad67d4858814ac24e618b8072900664  xtrans-1.6.0.tar.xz
146d770e564812e00f97e0cbdce632b7  libX11-1.8.12.tar.xz
e59476db179e48c1fb4487c12d0105d1  libXext-1.3.6.tar.xz
c5cc0942ed39c49b8fcd47a427bd4305  libFS-1.0.10.tar.xz
d1ffde0a07709654b20bada3f9abdd16  libICE-1.1.2.tar.xz
3aeeea05091db1c69e6f768e0950a431  libSM-1.2.6.tar.xz
e613751d38e13aa0d0fd8e0149cec057  libXScrnSaver-1.2.4.tar.xz
9acd189c68750b5028cf120e53c68009  libXt-1.3.1.tar.xz
85edefb7deaad4590a03fccba517669f  libXmu-1.2.1.tar.xz
05b5667aadd476d77e9b5ba1a1de213e  libXpm-3.5.17.tar.xz
2a9793533224f92ddad256492265dd82  libXaw-1.0.16.tar.xz
65b9ba1e9ff3d16c4fa72915d4bb585a  libXfixes-6.0.1.tar.xz
af0a5f0abb5b55f8411cd738cf0e5259  libXcomposite-0.4.6.tar.xz
4c54dce455d96e3bdee90823b0869f89  libXrender-0.9.12.tar.xz
5ce55e952ec2d84d9817169d5fdb7865  libXcursor-1.2.3.tar.xz
ca55d29fa0a8b5c4a89f609a7952ebf8  libXdamage-1.1.6.tar.xz
8816cc44d06ebe42e85950b368185826  libfontenc-1.1.8.tar.xz
66e03e3405d923dfaf319d6f2b47e3da  libXfont2-2.0.7.tar.xz
d378be0fcbd1f689f9a132e0d642bc4b  libXft-2.3.9.tar.xz
95a960c1692a83cc551979f7ffe28cf4  libXi-1.8.2.tar.xz
228c877558c265d2f63c56a03f7d3f21  libXinerama-1.1.5.tar.xz
24e0b72abe16efce9bf10579beaffc27  libXrandr-1.5.4.tar.xz
66c9e9e01b0b53052bb1d02ebf8d7040  libXres-1.2.2.tar.xz
b62dc44d8e63a67bb10230d54c44dcb7  libXtst-1.2.5.tar.xz
8a26503185afcb1bbd2c65e43f775a67  libXv-1.0.13.tar.xz
a90a5f01102dc445c7decbbd9ef77608  libXvMC-1.0.14.tar.xz
74d1acf93b83abeb0954824da0ec400b  libXxf86dga-1.1.6.tar.xz
d3db4b6dc924dc151822f5f7e79ae873  libXxf86vm-1.1.6.tar.xz
57c7efbeceedefde006123a77a7bc825  libpciaccess-0.18.1.tar.xz
229708c15c9937b6e5131d0413474139  libxkbfile-1.1.3.tar.xz
9805be7e18f858bed9938542ed2905dc  libxshmfence-1.3.3.tar.xz
bdd3ec17c6181fd7b26f6775886c730d  libXpresent-1.0.1.tar.xz
XEOF

for package in $(grep -v '^#' /tmp/lib-7.md5 | awk '{print $2}'); do
  packagedir=${package%.tar.?z*}
  tar -xf "$package"
  pushd "$packagedir"
    case $packagedir in
      libXfont2-*)
        ./configure $XORG_CONFIG --disable-devel-docs
        ;;
      libXt-*)
        ./configure $XORG_CONFIG \
                    --with-appdefaultdir=/etc/X11/app-defaults
        ;;
      libXpm-*)
        ./configure $XORG_CONFIG --disable-open-zfile
        ;;
      libpciaccess-*)
        mkdir build
        cd build
        meson setup --prefix=$XORG_PREFIX --buildtype=release ..
        ninja
        ninja install
        popd
        rm -rf "$packagedir"
        continue
        ;;
      *)
        ./configure $XORG_CONFIG
        ;;
    esac
    make
    make install
  popd
  rm -rf "$packagedir"
done
ldconfig
CMD
}

build_xcb_util() {
  run_step "xcb-util" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_xcb_util_extras() {
  run_step "XCB-Utilities" bash -e <<'CMD'
cat > /tmp/xcb-util-7.md5 << "XEOF"
a67bfac2eff696170259ef1f5ce1b611  xcb-util-image-0.4.1.tar.xz
fbdc05f86f72f287ed71b162f1a9725a  xcb-util-keysyms-0.4.1.tar.xz
193b890e2a89a53c31e2ece3afcbd55f  xcb-util-renderutil-0.3.10.tar.xz
581b3a092e3c0c1b4de6416d90b969c3  xcb-util-wm-0.4.2.tar.xz
bc30cd267b11ac5803fe19929cabd230  xcb-util-cursor-0.1.5.tar.xz
XEOF

for package in $(grep -v '^#' /tmp/xcb-util-7.md5 | awk '{print $2}'); do
  packagedir=${package%.tar.?z*}
  tar -xf "$package"
  pushd "$packagedir"
    ./configure $XORG_CONFIG
    make
    make install
  popd
  rm -rf "$packagedir"
done
ldconfig
CMD
}

build_libxcvt() {
  run_step "libxcvt" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=$XORG_PREFIX --buildtype=release ..
ninja
ninja install
CMD
}

build_libdrm() {
  run_step "libdrm" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=$XORG_PREFIX \
            --buildtype=release   \
            -D udev=true          \
            -D valgrind=disabled  \
            ..
ninja
ninja install
CMD
}

build_mesa() {
  run_step "Mesa" bash -e <<'CMD'
mkdir build
cd build
meson setup ..                    \
  --prefix=$XORG_PREFIX           \
  --buildtype=release             \
  -D platforms=x11,wayland        \
  -D gallium-drivers=auto         \
  -D vulkan-drivers=auto          \
  -D valgrind=disabled            \
  -D video-codecs=all             \
  -D libunwind=disabled
ninja
ninja install
CMD
}

build_xbitmaps() {
  run_step "xbitmaps" bash -e <<'CMD'
./configure $XORG_CONFIG
make install
CMD
}

build_xorg_apps() {
  run_step "Xorg-Applications" bash -e <<'CMD'
cat > /tmp/app-7.md5 << "XEOF"
30f898d71a7d8e817302970f1976198c  iceauth-1.0.10.tar.xz
7dcf5f702781bdd4aaff02e963a56270  mkfontscale-1.2.3.tar.xz
b9efe1d21615c474b22439d41981beef  sessreg-1.1.4.tar.xz
1d61c9f4a3d1486eff575bf233e5776c  setxkbmap-1.3.4.tar.xz
6484cd8ee30354aaaf8f490988f5f6ef  smproxy-1.0.8.tar.xz
bf7b5a94561c7c98de447ea53afabfc4  xauth-1.1.4.tar.xz
37063ccf902fe3d55a90f387ed62fe1f  xcmsdb-1.0.7.tar.xz
f97e81b2c063f6ae9b18d4b4be7543f6  xcursorgen-1.0.9.tar.xz
700556957773d378fa16a65a4406be0a  xdpyinfo-1.4.0.tar.xz
830a54ef3ba338013e06a1b5b012b4bd  xdriinfo-1.0.8.tar.xz
f29d1544f8dd126a1b85e2f7f728672d  xev-1.2.6.tar.xz
687e42aa5afaec37f14da3072651c635  xgamma-1.0.8.tar.xz
45c7e956941194e5f06a9c7307f5f971  xhost-1.0.10.tar.xz
8e4d14823b7cbefe1581c398c6ab0035  xinput-1.6.4.tar.xz
83d711948de9ccac550d2f4af50e94c3  xkbcomp-1.4.7.tar.xz
543c0535367ca30e0b0dbcfa90fefdf9  xkbevd-1.1.6.tar.xz
07483ddfe1d83c197df792650583ff20  xkbutils-1.0.6.tar.xz
f62b99839249ce9a7a8bb71a5bab6f9d  xkill-1.0.6.tar.xz
da5b7a39702841281e1d86b7349a03ba  xlsatoms-1.1.4.tar.xz
ab4b3c47e848ba8c3e47c021230ab23a  xlsclients-1.1.5.tar.xz
ba2dd3db3361e374fefe2b1c797c46eb  xmessage-1.0.7.tar.xz
0d66e07595ea083871048c4b805d8b13  xmodmap-1.0.11.tar.xz
ab6c9d17eb1940afcfb80a72319270ae  xpr-1.2.0.tar.xz
5ef4784b406d11bed0fdf07cc6fba16c  xprop-1.2.8.tar.xz
dc7680201afe6de0966c76d304159bda  xrandr-1.5.3.tar.xz
c8629d5a0bc878d10ac49e1b290bf453  xrdb-1.2.2.tar.xz
55003733ef417db8fafce588ca74d584  xrefresh-1.1.0.tar.xz
18ff5cdff59015722431d568a5c0bad2  xset-1.2.5.tar.xz
fa9a24fe5b1725c52a4566a62dd0a50d  xsetroot-1.1.3.tar.xz
d698862e9cad153c5fefca6eee964685  xvinfo-1.1.5.tar.xz
b0081fb92ae56510958024242ed1bc23  xwd-1.0.9.tar.xz
c91201bc1eb5e7b38933be8d0f7f16a8  xwininfo-1.1.6.tar.xz
3e741db39b58be4fef705e251947993d  xwud-1.0.7.tar.xz
XEOF

for package in $(grep -v '^#' /tmp/app-7.md5 | awk '{print $2}'); do
  packagedir=${package%.tar.?z*}
  tar -xf "$package"
  pushd "$packagedir"
    ./configure $XORG_CONFIG
    make
    make install
  popd
  rm -rf "$packagedir"
done
rm -f $XORG_PREFIX/bin/xkeystone
CMD
}

build_luit() {
  run_step "luit" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_xcursor_themes() {
  run_step "xcursor-themes" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_xkeyboard_config() {
  run_step "xkeyboard-config" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=$XORG_PREFIX --buildtype=release ..
ninja
ninja install
CMD
}

build_xorg_fonts() {
  run_step "Xorg-Fonts" bash -e <<'CMD'
cat > /tmp/font-7.md5 << "XEOF"
a6541d12ceba004c0c1e3df900324642  font-util-1.4.1.tar.xz
a56b1a7f2c14173f71f010225fa131f1  encodings-1.1.0.tar.xz
79f4c023e27d1db1dfd90d041ce89835  font-alias-1.0.5.tar.xz
546d17feab30d4e3abcf332b454f58ed  font-adobe-utopia-type1-1.0.5.tar.xz
063bfa1456c8a68208bf96a33f472bb1  font-bh-ttf-1.0.4.tar.xz
51a17c981275439b85e15430a3d711ee  font-bh-type1-1.0.4.tar.xz
00f64a84b6c9886040241e081347a853  font-ibm-type1-1.0.4.tar.xz
fe972eaf13176fa9aa7e74a12ecc801a  font-misc-ethiopic-1.0.5.tar.xz
3b47fed2c032af3a32aad9acc1d25150  font-xfree86-type1-1.0.5.tar.xz
XEOF

for package in $(grep -v '^#' /tmp/font-7.md5 | awk '{print $2}'); do
  packagedir=${package%.tar.?z*}
  tar -xf "$package"
  pushd "$packagedir"
    ./configure $XORG_CONFIG
    make
    make install
  popd
  rm -rf "$packagedir"
done
ln -svfn $XORG_PREFIX/share/fonts/X11/OTF /usr/share/fonts/X11-OTF
ln -svfn $XORG_PREFIX/share/fonts/X11/TTF /usr/share/fonts/X11-TTF
CMD
}

build_xorg_server() {
  run_step "Xorg-Server" bash -e <<'CMD'
mkdir build
cd build
meson setup ..                          \
  --prefix=$XORG_PREFIX                 \
  --localstatedir=/var                  \
  -D glamor=true                        \
  -D systemd_logind=true                \
  -D xkb_output_dir=/var/lib/xkb
ninja
ninja install
mkdir -pv /etc/X11/xorg.conf.d
install -v -d -m1777 /tmp/.ICE-unix /tmp/.X11-unix
cat >> /etc/sysconfig/createfiles << "XEOF"
/tmp/.ICE-unix dir 1777 root root
/tmp/.X11-unix dir 1777 root root
XEOF
CMD
}

build_libevdev() {
  run_step "libevdev" bash -e <<'CMD'
mkdir build
cd build
meson setup .. --prefix=$XORG_PREFIX    \
               --buildtype=release      \
               -D documentation=disabled \
               -D tests=disabled
ninja
ninja install
CMD
}

build_xf86_input_evdev() {
  run_step "xf86-input-evdev" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_libinput() {
  run_step "libinput" bash -e <<'CMD'
mkdir build
cd build
meson setup ..                          \
  --prefix=$XORG_PREFIX                 \
  --buildtype=release                   \
  -D debug-gui=false                    \
  -D tests=false                        \
  -D libwacom=false                     \
  -D udev-dir=/usr/lib/udev
ninja
ninja install
CMD
}

build_xf86_input_libinput() {
  run_step "xf86-input-libinput" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_xf86_input_synaptics() {
  run_step "xf86-input-synaptics" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_xf86_input_wacom() {
  run_step "xf86-input-wacom" bash -e <<'CMD'
./configure $XORG_CONFIG --with-systemd-unit-dir=no
make
make install
CMD
}

build_xwayland() {
  run_step "Xwayland" bash -e <<'CMD'
sed -i '/install_man/,$d' meson.build
mkdir build
cd build
meson setup ..                          \
  --prefix=$XORG_PREFIX                 \
  --buildtype=release                   \
  -D xkb_output_dir=/var/lib/xkb
ninja
ninja install
if ! grep -q '.X11-unix' /etc/sysconfig/createfiles 2>/dev/null; then
  cat >> /etc/sysconfig/createfiles << "XEOF"
/tmp/.X11-unix dir 1777 root root
XEOF
fi
CMD
}

build_xterm() {
  run_step "xterm" bash -e <<'CMD'
sed -i '/v0/{n;s/new:/new:kb=^?:/}' termcap
printf '\tkbs=\\177,\n' >> terminfo

TERMINFO=/usr/share/terminfo \
./configure $XORG_CONFIG     \
            --with-app-defaults=/etc/X11/app-defaults
make
make install
mkdir -pv /usr/share/applications
cp -v *.desktop /usr/share/applications/
CMD
}

build_xclock() {
  run_step "xclock" bash -e <<'CMD'
./configure $XORG_CONFIG
make
make install
CMD
}

build_twm() {
  run_step "twm" bash -e <<'CMD'
sed -i -e '/^rcdir =/s,^\(rcdir = \).*,\1/etc/X11/app-defaults,' src/Makefile.in
./configure $XORG_CONFIG
make
make install
CMD
}

build_xinit() {
  run_step "xinit" bash -e <<'CMD'
./configure $XORG_CONFIG \
            --with-xinitdir=/etc/X11/app-defaults
make
make install
ldconfig
CMD
}

build_xorg_legacy() {
  run_step "Xorg-Legacy" bash -e <<'CMD'
cat > /tmp/legacy-7.md5 << "XEOF"
e09b61567ab4a4d534119bba24eddfb1  bdftopcf-1.1.1.tar.xz
20239f6f99ac586f10360b0759f73361  font-adobe-100dpi-1.0.4.tar.xz
2dc044f693ee8e0836f718c2699628b9  font-adobe-75dpi-1.0.4.tar.xz
2c939d5bd4609d8e284be9bef4b8b330  font-jis-misc-1.0.4.tar.xz
6300bc99a1e45fbbe6075b3de728c27f  font-daewoo-misc-1.0.4.tar.xz
fe2c44307639062d07c6e9f75f4d6a13  font-isas-misc-1.0.4.tar.xz
145128c4b5f7820c974c8c5b9f6ffe94  font-misc-misc-1.1.3.tar.xz
XEOF

for package in $(grep -v '^#' /tmp/legacy-7.md5 | awk '{print $2}'); do
  packagedir=${package%.tar.?z*}
  tar -xf "$package"
  pushd "$packagedir"
    ./configure $XORG_CONFIG
    make
    make install
  popd
  rm -rf "$packagedir"
done
ldconfig
CMD
}

# Chapter 25: Graphical Environment Libraries

build_at_spi2_core() {
  run_step "at-spi2-core" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_atkmm() {
  run_step "atkmm" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_cairo() {
  run_step "cairo" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_cairomm() {
  run_step "cairomm" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_colord_gtk() {
  run_step "colord-gtk" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            -D vapi=true \
            -D docs=false ..
ninja
ninja install
CMD
}

build_fltk() {
  run_step "fltk" bash -e <<'CMD'
./configure --prefix=/usr \
            --enable-shared
make
make install
CMD
}

build_freeglut() {
  run_step "freeglut" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr       \
      -D CMAKE_BUILD_TYPE=Release        \
      -D FREEGLUT_BUILD_DEMOS=OFF        \
      -D FREEGLUT_BUILD_STATIC_LIBS=OFF  \
      -G Ninja ..
ninja
ninja install
CMD
}

build_gdk_pixbuf() {
  run_step "gdk-pixbuf" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release \
            --wrap-mode=nofallback ..
ninja
ninja install
CMD
}

build_glew() {
  run_step "glew" bash -e <<'CMD'
sed -i 's%lib64%lib%g' config/Makefile.linux
sed -i -e '/glew.lib.static/d' Makefile
make
make install.all GLEW_DEST=/usr
chmod -v 755 /usr/lib/libGLEW.so
CMD
}

build_glslang() {
  run_step "glslang" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr   \
      -D CMAKE_BUILD_TYPE=Release    \
      -D ALLOW_EXTERNAL_SPIRV_TOOLS=ON \
      -D BUILD_SHARED_LIBS=ON        \
      -G Ninja ..
ninja
ninja install
CMD
}

build_glu() {
  run_step "glu" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_goffice() {
  run_step "goffice" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_graphene() {
  run_step "graphene" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_gtk3() {
  run_step "gtk3" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr        \
            --buildtype=release  \
            -D man=true          \
            -D broadway_backend=true ..
ninja
ninja install
CMD
}

build_gtk4() {
  run_step "gtk4" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr        \
            --buildtype=release  \
            -D broadway-backend=true \
            -D vulkan=enabled ..
ninja
ninja install
CMD
}

build_gtkmm() {
  run_step "gtkmm" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_gtk_vnc() {
  run_step "gtk-vnc" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_gtksourceview4() {
  run_step "gtksourceview4" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_gtksourceview5() {
  run_step "gtksourceview5" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_imlib2() {
  run_step "imlib2" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static
make
make install
CMD
}

build_keybinder3() {
  run_step "keybinder3" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

build_libadwaita() {
  run_step "libadwaita" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_libei() {
  run_step "libei" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_libepoxy() {
  run_step "libepoxy" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_libhandy() {
  run_step "libhandy" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_libnotify() {
  run_step "libnotify" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr       \
            --buildtype=release \
            -D man=false        \
            -D gtk_doc=false ..
ninja
ninja install
CMD
}

build_pango() {
  run_step "pango" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_pangomm() {
  run_step "pangomm" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_qt6() {
  run_step "qt6" bash -e <<'CMD'
./configure -prefix /usr                       \
            -sysconfdir /etc/xdg               \
            -archdatadir /usr/lib/qt6          \
            -datadir /usr/share/qt6            \
            -examplesdir /usr/share/doc/qt6/examples \
            -headerdir /usr/include/qt6        \
            -libdir /usr/lib                   \
            -nomake examples                   \
            -nomake tests                      \
            -system-sqlite
cmake --build . --parallel
cmake --install .
CMD
}

build_vulkan_headers() {
  run_step "vulkan-headers" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -G Ninja ..
ninja
ninja install
CMD
}

build_vulkan_loader() {
  run_step "vulkan-loader" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr       \
      -D CMAKE_BUILD_TYPE=Release        \
      -D CMAKE_INSTALL_SYSCONFDIR=/etc   \
      -D VULKAN_HEADERS_INSTALL_DIR=/usr \
      -G Ninja ..
ninja
ninja install
CMD
}

build_webkitgtk() {
  run_step "webkitgtk" bash -e <<'CMD'
mkdir -p buildgtk4
cd buildgtk4
cmake -D CMAKE_BUILD_TYPE=Release          \
      -D CMAKE_INSTALL_PREFIX=/usr         \
      -D CMAKE_SKIP_RPATH=ON              \
      -D PORT=GTK                          \
      -D LIB_INSTALL_DIR=/usr/lib         \
      -D USE_LIBHYPHEN=OFF                \
      -D ENABLE_GAMEPAD=OFF               \
      -D ENABLE_MINIBROWSER=ON            \
      -D ENABLE_DOCUMENTATION=OFF         \
      -D USE_GTK4=ON                       \
      -D USE_SOUP2=OFF                     \
      -G Ninja ..
ninja
ninja install
CMD
}

build_xdg_desktop_portal() {
  run_step "xdg-desktop-portal" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_xdg_desktop_portal_gtk() {
  run_step "xdg-desktop-portal-gtk" bash -e <<'CMD'
mkdir build
cd build
meson setup --prefix=/usr \
            --buildtype=release ..
ninja
ninja install
CMD
}

build_startup_notification() {
  run_step "startup-notification" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static
make
make install
CMD
}

build_libxklavier() {
  run_step "libxklavier" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static
make
make install
CMD
}

build_kcolorpicker() {
  run_step "kColorPicker" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D BUILD_SHARED_LIBS=ON      \
      -G Ninja ..
ninja
ninja install
CMD
}

build_kimageannotator() {
  run_step "kImageAnnotator" bash -e <<'CMD'
mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr \
      -D CMAKE_BUILD_TYPE=Release  \
      -D BUILD_SHARED_LIBS=ON      \
      -G Ninja ..
ninja
ninja install
CMD
}

# Chapter 21: Mail Server Software

build_dovecot() {
  run_step "dovecot" bash -e <<'CMD'
groupadd -g 42 dovecot 2>/dev/null || true
useradd -c "Dovecot unprivileged" -d /dev/null -u 42 \
        -g dovecot -s /bin/false dovecot 2>/dev/null || true
groupadd -g 43 dovenull 2>/dev/null || true
useradd -c "Dovecot login unprivileged" -d /dev/null -u 43 \
        -g dovenull -s /bin/false dovenull 2>/dev/null || true

./configure --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            --with-systemdsystemunitdir=no \
            --docdir=/usr/share/doc/dovecot-2.3.21 \
            --disable-static
make
make install
CMD
}

build_exim() {
  run_step "exim" bash -e <<'CMD'
groupadd -g 31 exim 2>/dev/null || true
useradd -d /dev/null -c "Exim Daemon" -g exim -s /bin/false \
        -u 31 exim 2>/dev/null || true

sed -e 's,^BIN_DIR.*$,BIN_DIRECTORY=/usr/sbin,'  \
    -e 's,^CONF.*$,CONFIGURE_FILE=/etc/exim.conf,' \
    -e 's,^EXIM_USER.*$,EXIM_USER=exim,'           \
    -e '/EXIM_MONITOR/s/EXIM_MONITOR/# EXIM_MONITOR/' \
    -e '/^EXIM_TMPDIR/d'                             \
    src/EDITME > Local/Makefile

make
make install
install -v -m755 -d /var/spool/exim
install -v -m750 -o exim -g exim -d /var/spool/exim
install -v -m750 -o exim -g exim -d /var/log/exim
CMD
}

build_postfix() {
  run_step "postfix" bash -e <<'CMD'
groupadd -g 32 postfix 2>/dev/null || true
useradd -c "Postfix Daemon User" -d /var/spool/postfix -g postfix \
        -s /bin/false -u 32 postfix 2>/dev/null || true
groupadd -g 33 postdrop 2>/dev/null || true

make CCARGS="-DUSE_TLS -I/usr/include/openssl \
             -DUSE_SASL_AUTH -DUSE_CYRUS_SASL -I/usr/include/sasl" \
     AUXLIBS="-lssl -lcrypto -lsasl2" \
     makefiles
make

sh postfix-install -non-interactive \
   daemon_directory=/usr/lib/postfix \
   manpage_directory=/usr/share/man \
   html_directory=/usr/share/doc/postfix-3.9.1/html \
   readme_directory=/usr/share/doc/postfix-3.9.1/readme
CMD
}

build_sendmail() {
  run_step "sendmail" bash -e <<'CMD'
groupadd -g 26 smmsp 2>/dev/null || true
useradd -c "Sendmail Daemon" -g smmsp -d /dev/null \
        -s /bin/false -u 26 smmsp 2>/dev/null || true

cat >> devtools/Site/site.config.m4 << "EOF"
APPENDDEF(`confENVDEF',`-DSTARTTLS')
APPENDDEF(`confLIBS', `-lssl -lcrypto')
APPENDDEF(`confINCDIRS', `-I/usr/include/openssl')
EOF

cd sendmail
sh Build
cd ../cf/cf
cp generic-linux.mc sendmail.mc
sh Build sendmail.cf
cd ../..

install -v -d -m755 /etc/mail
install -v -m644 cf/cf/sendmail.cf /etc/mail
install -v -m644 cf/cf/submit.cf   /etc/mail

for dir in libexec mail sbin; do
  install -v -d /usr/$dir
done
cd sendmail
sh Build install
CMD
}

# Chapter 22: Databases

build_lmdb() {
  run_step "lmdb" bash -e <<'CMD'
cd libraries/liblmdb
make
sed -i 's| liblmdb.a||' Makefile
make prefix=/usr install
CMD
}

build_mariadb() {
  run_step "mariadb" bash -e <<'CMD'
groupadd -g 40 mysql 2>/dev/null || true
useradd -c "MySQL Server" -d /srv/mysql -g mysql \
        -s /bin/false -u 40 mysql 2>/dev/null || true

mkdir build
cd build
cmake -D CMAKE_INSTALL_PREFIX=/usr      \
      -D CMAKE_BUILD_TYPE=Release       \
      -D INSTALL_DOCDIR=share/doc/mariadb-11.4.5 \
      -D INSTALL_DOCREADMEDIR=share/doc/mariadb-11.4.5 \
      -D INSTALL_MANDIR=share/man       \
      -D INSTALL_MYSQLSHAREDIR=share/mysql \
      -D INSTALL_MYSQLTESTDIR=share/mysql/test \
      -D INSTALL_PLUGINDIR=lib/mysql/plugin \
      -D INSTALL_SBINDIR=sbin           \
      -D INSTALL_SCRIPTDIR=bin          \
      -D INSTALL_SQLBENCHDIR=share/mysql/bench \
      -D INSTALL_SUPPORTFILESDIR=share/mysql \
      -D MYSQL_DATADIR=/srv/mysql       \
      -D MYSQL_UNIX_ADDR=/run/mysqld/mysqld.sock \
      -D WITH_EXTRA_CHARSETS=complex    \
      -D WITH_SSL=system                \
      -D SKIP_TESTS=ON                  \
      ..
make
make install

install -v -dm 755 /etc/mysql
cat > /etc/mysql/my.cnf << "EOF"
[mysqld]
skip-networking
datadir=/srv/mysql
EOF

install -v -dm 755 -o mysql -g mysql /srv/mysql /run/mysqld
mariadb-install-db --basedir=/usr --datadir=/srv/mysql --user=mysql
CMD
}

build_postgresql() {
  run_step "postgresql" bash -e <<'CMD'
groupadd -g 41 postgres 2>/dev/null || true
useradd -c "PostgreSQL Server" -g postgres -d /srv/pgsql/data \
        -s /bin/false -u 41 postgres 2>/dev/null || true

./configure --prefix=/usr       \
            --enable-thread-safety \
            --docdir=/usr/share/doc/postgresql-17.2
make
make install

install -v -dm 700 -o postgres -g postgres /srv/pgsql/data
install -v -dm 755 -o postgres -g postgres /run/postgresql
su - postgres -c '/usr/bin/initdb -D /srv/pgsql/data'
CMD
}

build_sqlite() {
  run_step "sqlite" bash -e <<'CMD'
./configure --prefix=/usr                 \
            --disable-static              \
            --enable-fts5                 \
            CPPFLAGS="-DSQLITE_ENABLE_FTS3=1            \
                      -DSQLITE_ENABLE_FTS3_TOKENIZER=1  \
                      -DSQLITE_ENABLE_FTS4=1            \
                      -DSQLITE_ENABLE_COLUMN_METADATA=1 \
                      -DSQLITE_SECURE_DELETE=1           \
                      -DSQLITE_ENABLE_UNLOCK_NOTIFY=1    \
                      -DSQLITE_ENABLE_DBSTAT_VTAB=1"
make
make install
CMD
}

# Chapter 23: Other Server Software

build_openldap() {
  run_step "openldap" bash -e <<'CMD'
groupadd -g 39 ldap 2>/dev/null || true
useradd -c "OpenLDAP Daemon Owner" -d /var/lib/openldap -u 39 \
        -g ldap -s /bin/false ldap 2>/dev/null || true

autoconf
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-static  \
            --enable-dynamic  \
            --enable-crypt    \
            --enable-spasswd  \
            --enable-slapd    \
            --enable-modules  \
            --enable-rlookups \
            --enable-backends=mod \
            --disable-sql     \
            --enable-overlays=mod
make depend
make
make install

sed -i '/\.telecom/d' /etc/openldap/ldap.conf

install -v -dm700 -o ldap -g ldap /var/lib/openldap
install -v -dm700 -o ldap -g ldap /etc/openldap/slapd.d
CMD
}

build_unbound() {
  run_step "unbound" bash -e <<'CMD'
groupadd -g 88 unbound 2>/dev/null || true
useradd -c "Unbound DNS Resolver" -d /var/lib/unbound -u 88 \
        -g unbound -s /bin/false unbound 2>/dev/null || true

./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-static  \
            --with-pidfile=/run/unbound.pid
make
make install
install -v -m755 -d /var/lib/unbound
CMD
}

main "$@"
