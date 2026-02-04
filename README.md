# CodexLFS

Build automation scripts for [Linux From Scratch](https://www.linuxfromscratch.org/lfs/) (LFS) and [Beyond Linux From Scratch](https://www.linuxfromscratch.org/blfs/) (BLFS).

## Features

- **Automated LFS Build** – Complete Linux From Scratch system build via `LFS_Build.sh`
- **BLFS Automation** – 300+ package build functions in `BLFS_Build.sh`
- **Dynamic Fetching** – Automatically downloads build instructions for uncovered packages
- **Selective Builds** – Run specific chapters with `--chapters` option

## Quick Start

```bash
# Build base LFS system
./LFS_Build.sh

# Build BLFS packages (all chapters)
./BLFS_Build.sh

# Build only specific chapters
./BLFS_Build.sh --chapters 5,6
```

## BLFS Coverage

| Chapters | Topic | Status |
|----------|-------|--------|
| 4–8 | Security, Filesystems, Editors, Shells, Virtualization | ✅ Full |
| 9–15 | Libraries, Graphics, Utilities, Programming, Networking | ⚡ Partial |
| 16–20 | Networking Tools & Servers | ⚡ Partial |
| 21–50 | X Window, KDE, GNOME, Multimedia, Printing | 🔄 Dynamic |

### Explicit Package Coverage

<details>
<summary>Click to expand full package list</summary>

**Libraries (Ch 9–10)**
- `babl`, `Exiv2`, `FriBidi`, `gegl`, `libmng`, `libraw`, `librsvg`, `libwebp`, `OpenJPEG`

**Utilities (Ch 11–12)**
- `asciidoctor`, `bogofilter`, `desktop-file-utils`, `glslc`
- `BlueZ`, `Bubblewrap`, `Colord`, `cpio`, `cups-pk-helper`, `elogind`, `lm-sensors`
- `autofs`, `hwdata`, `LSB-Tools`, `notification-daemon`, `pm-utils`
- `power-profiles-daemon`, `raptor`, `rasqal`, `redland`, `sg3_utils`, `sysmond`, `sysmon3`

**Programming (Ch 13)**
- `Clisp`, `GCC`, `GDB`, `dtc`, `GC`, `patchelf`, `Guile`, `luajit`
- `Valgrind`, `Vala`, `LLVM`, `OpenJDK`, `yasm`, `Ruby`, `Rustc`, `rust-bindgen`
- `SCons`, `slang`, `Subversion`, `SWIG`, `Tk`, `unifdef`, `apache-ant`

**Networking (Ch 14–20)**
- `NcFTP`, `ntp`, `rpcbind`, `Samba`, `iw`, `Wireless Tools`, `wpa_supplicant`
- `Avahi`, `NetworkManager`, `Wireshark`, `cURL`, `libevent`, `libsoup`
- `Links`, `Lynx`, `Mutt`, `Procmail`, `GeoClue`, `Fetchmail`, `Apache`

**Python Modules**
- `cssselect`, `Cython`, `docutils` (Python 3.11.1 included)

</details>

## Project Structure

```
CodexLFS/
├── LFS_Build.sh           # Base LFS build automation
├── BLFS_Build.sh          # BLFS package automation (300+ build functions)
├── fetch_blfs_sections.py # Helper to fetch BLFS commands from website
└── CONTRIBUTING.md        # Developer guide
```

## For Developers

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Adding new package build functions
- Using `fetch_blfs_sections.py` to retrieve build commands
- Priority packages for implementation

### Fetch Build Commands

```bash
# Requires: pip install requests beautifulsoup4
./fetch_blfs_sections.py general/ch9
```

## Resources

- [LFS Book](https://www.linuxfromscratch.org/lfs/view/stable/)
- [BLFS Book](https://www.linuxfromscratch.org/blfs/view/stable/)
