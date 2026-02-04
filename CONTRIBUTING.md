# BLFS Development Guide

## Current State

**Over 300 explicit `build_*` functions** in `BLFS_Build.sh`.

### Covered (Explicit)
| Ch | Topic | Status |
|----|-------|--------|
| 4-8 | Security, FileSys, Editors, Shells, Virt | Full |
| 9-15 | Libs, Graphics, Utils, Programming, Net | Partial |
| 16-20 | Net Tools/Servers | Partial |

### Not Covered (Dynamic Fetch) - Highlights
Chapters 21-50 rely on dynamic fetching. Key areas include:
| Ch | Topic |
|----|-------|
| 21-23 | Additional Servers |
| 24-25 | X Window, Graphical Browsers |
| 27 | Window Managers |
| 29-31 | KDE (Frameworks, Gear, Plasma) |
| 33-34 | GNOME (Libs, Utils) |
| 42-45 | Multimedia |
| 46-50 | Printing, Scanning, SGML, PS, Typesetting |

## Adding New Packages

1. **Add build function:**
```bash
build_pkgname() {
  run_step "pkgname" bash -e <<'CMD'
# Build commands from BLFS
./configure --prefix=/usr
make
make install
CMD
}
```

2. **Add case match in `main()`:**
```bash
pkgname-*) build_pkgname ;;
```

3. **Use helper to fetch commands:**
```bash
# Argument is a BLFS URL path segment, e.g. "general/ch9", not just "9"
# Requires: pip install requests beautifulsoup4
./fetch_blfs_sections.py general/ch9
```

## Priority Packages

High-value targets for explicit implementation:

1. **X Window (Ch 24)**: Xorg, Mesa, libdrm
2. **Browsers (Ch 25)**: Firefox, Chromium
3. **Multimedia (Ch 42-44)**: FFmpeg, PulseAudio, ALSA
4. **GNOME core (Ch 33-34)**: GTK, GDK-Pixbuf
5. **KDE core (Ch 29)**: Qt, KDE Frameworks

## File Structure

```
BLFS_Build.sh     # Main script (large multi-thousand-line build script)
fetch_blfs_sections.py  # Fetch BLFS commands
LFS_Build.sh      # Base LFS build
```

## Testing

```bash
# Run only specific chapters
./BLFS_Build.sh --chapters 5,6

# Fetch commands only (no execution)
# Requires: pip install requests beautifulsoup4
./fetch_blfs_sections.py general/ch9
```
