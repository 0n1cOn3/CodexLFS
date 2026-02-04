# Codex Instructions for CodexLFS

## Summary
Automates LFS/BLFS builds. 300+ explicit `build_*` functions in `BLFS_Build.sh`.

## Files
- `BLFS_Build.sh` - BLFS automation
- `LFS_Build.sh` - Base LFS
- `fetch_blfs_sections.py` - Fetch BLFS commands

## Coverage
- Ch 4-20: Explicit functions
- Ch 21-50: Dynamic fetch

## Add Package
```bash
# 1. Build function
build_pkg() {
  run_step "pkg" bash -e <<'CMD'
./configure --prefix=/usr
make
make install
CMD
}

# 2. Case match in main()
pkg-*) build_pkg ;;
```

## Fetch Commands
```bash
pip install requests beautifulsoup4
./fetch_blfs_sections.py general/ch9
```

## Test
```bash
./BLFS_Build.sh --chapters 5,6
```

## Priority
1. X Window (Ch 24)
2. Browsers (Ch 25)
3. Multimedia (Ch 42-44)
4. GNOME (Ch 33-34)
5. KDE (Ch 29)
