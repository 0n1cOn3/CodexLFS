# Claude Instructions for CodexLFS

## Context
CodexLFS automates LFS/BLFS builds. Main script: `BLFS_Build.sh` with 300+ `build_*` functions.

## Architecture
```
BLFS_Build.sh           # Main BLFS script
├── run_step()          # Logging wrapper
├── build_*()           # Package build functions
└── main()              # Case dispatch by package name
fetch_blfs_sections.py  # Fetch commands from BLFS site
LFS_Build.sh            # Base LFS build
```

## Coverage Map
| Chapters | Status | Topics |
|----------|--------|--------|
| 4-20 | Explicit | Security, FileSys, Editors, Shells, Virt, Libs, Utils, Net |
| 21-50 | Dynamic | X Window, WMs, KDE, GNOME, Multimedia, Print, Scan |

## Code Patterns

### Build Function Template
```bash
build_pkgname() {
  run_step "pkgname" bash -e <<'CMD'
./configure --prefix=/usr \
            --disable-static
make
make install
CMD
}
```

### Case Match Pattern
```bash
# In main() function
pkgname-*) build_pkgname ;;
```

### Dynamic Fallback
```bash
*) run_package "$name" "$path" ;;  # Fetches from BLFS site
```

## Development Workflow
1. Find package in BLFS book
2. Fetch commands: `./fetch_blfs_sections.py SECTION_PATH`
3. Create `build_*` function
4. Add case match in `main()`
5. Test: `./BLFS_Build.sh --chapters N`

## Dependencies for fetch script
```bash
pip install requests beautifulsoup4
```

## High-Priority Packages
- X Window: Xorg, Mesa, libdrm
- Browsers: Firefox, Chromium  
- Multimedia: FFmpeg, PulseAudio, ALSA
- Desktop: GTK, Qt, KDE Frameworks
