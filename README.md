# CodexLFS

A build script that automates the Linux From Scratch process.

## BLFS Automation

`BLFS_Build.sh` extends the base LFS system using instructions from the [BLFS stable book](https://www.linuxfromscratch.org/blfs/view/stable/). For Chapters 4 through 9 and much of Chapters 10 through 15, the script contains explicit build commands for many packages. Recent updates expand Chapter 10 coverage with libraries such as `babl`, `Exiv2`, `FriBidi`, `gegl`, `libmng`, `libraw`, `librsvg`, `libwebp`, and `OpenJPEG`. Chapter 11 utilities including `asciidoctor`, `bogofilter`, `desktop-file-utils`, and `glslc` are scripted as well. Chapter 12 now includes utilities like `BlueZ`, `Bubblewrap`, `Colord`, `cpio`, `cups-pk-helper`, `elogind`, and `lm-sensors`, `autofs`, `hwdata`, `LSB-Tools`, `notification-daemon`, `pm-utils`, `power-profiles-daemon`, `raptor`, `rasqal`, `redland`, `sg3_utils`, `sysmond` and `sysmon3`. Networking programs such as `NcFTP`, `ntp`, `rpcbind`, `Samba`, `iw`, `Wireless Tools`, and `wpa_supplicant` are handled automatically; programming tools like `Clisp`, `GCC` and `GDB` are built directly. Additional utilities such as `GPM` and `blocaled` and development tools `dtc`, `GC`, `patchelf`, `Guile`, `luajit`, `Valgrind`, `Vala`, `LLVM`, `OpenJDK`, and `yasm` are now scripted. Programming coverage also includes tools like `Ruby`, `Rustc`, `rust-bindgen`, `SCons`, `slang`, `Subversion`, `SWIG`, `Tk`, `unifdef`, and `apache-ant`. Chapter 16 networking tools including `Avahi`, `NetworkManager`, and `Wireshark` build directly from the script. Remaining packages are downloaded on the fly from the BLFS site. By default all chapters 4 through 50 are processed, but you can limit execution with the `--chapters` option, for example `./BLFS_Build.sh --chapters 5,6` to run chapters 5 and 6 only.

It also includes Python 3.11.1 for compatibility.
Additional Python modules including `cssselect`, `Cython`, and `docutils` are
installed automatically.
