# Copilot Instructions for CodexLFS

## Project Overview
CodexLFS automates Linux From Scratch (LFS) and Beyond LFS (BLFS) builds.

## Key Files
- `BLFS_Build.sh`: Main BLFS automation script (300+ `build_*` functions)
- `LFS_Build.sh`: Base LFS build script
- `fetch_blfs_sections.py`: Fetches BLFS commands from website

## BLFS Coverage
- **Explicit**: Ch 4-20 (Security, FileSys, Editors, Shells, Virt, Libs, Utils, Programming, Networking)
- **Dynamic**: Ch 21-50 (X Window, KDE, GNOME, Multimedia, Printing)

## Adding Packages

### 1. Create build function
```bash
build_pkgname() {
  run_step "pkgname" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}
```

### 2. Add case match in main()
```bash
pkgname-*) build_pkgname ;;
```

### 3. Fetch commands
```bash
# Requires: pip install requests beautifulsoup4
./fetch_blfs_sections.py general/ch9
```

## Conventions
- Use `run_step` wrapper for all build commands
- Follow BLFS book order for package dependencies
- Use heredocs with `<<'CMD'` for multi-line commands
- Match package names with glob patterns (e.g., `pkgname-*`)

## Testing
```bash
# Run specific chapters only
./BLFS_Build.sh --chapters 5,6
```

## Priority Targets
1. X Window (Ch 24): Xorg, Mesa, libdrm
2. Browsers (Ch 25): Firefox, Chromium
3. Multimedia (Ch 42-44): FFmpeg, PulseAudio, ALSA
4. GNOME core (Ch 33-34): GTK, GDK-Pixbuf
5. KDE core (Ch 29): Qt, KDE Frameworks
