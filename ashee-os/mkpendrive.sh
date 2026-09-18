#!/usr/bin/env bash
#
# Ashee OS -- the pen-drive image. The base system plus git, plus tar, plus the archive.
#
# ## What this is for
#
# A bootable, self-contained copy for testing. Boot any machine from the drive and the archive is
# there, with the tools to restore it. Nothing is written to the host's disk and nothing runs from it.
#
# ## What was added, and why each one
#
#   git    -- `git clone <bundle>` and `git bundle verify`. **The receiver needs this, not the drive**,
#             which is why the base image does not have it and this one does.
#   tar    -- the base image has no `tar` and no `gzip`. Without them the archive's tarballs are
#             files this operating system cannot open, which would make the drive a container rather
#             than a usable copy.
#   gzip   -- same reason.
#   /archive -- the bundles, the tarballs, the checksums and the manifest, uncompressed and browsable.
#
# ## Why the base script was not edited
#
# `mkinitramfs.sh` measures the smallest thing that is an operating system, and its number is the
# point. Adding 60 MB of archive to it would destroy the measurement. This script is a separate
# artifact built from the same approach, and it says so.
set -uo pipefail

OUT="${1:-/tmp/ashee-pendrive}"
SRC="$(cd "$(dirname "$0")" && pwd)"
KERNEL="/boot/vmlinuz-$(uname -r)"
ARCHIVE=/home/asheegaming/ashee-archive
[ -f "$KERNEL" ] || { echo "no bootable kernel at $KERNEL" >&2; exit 1; }
[ -d "$ARCHIVE" ] || { echo "no archive at $ARCHIVE -- run the archive build first" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/root"/{bin,dev,proc,sys,tmp,run,archive}
R="$OUT/root"

# The base tools, plus everything the init and the tests actually call.
#
# **This list is the whole lesson of the pen-drive build.** The first version carried the base tools
# and nothing else, and it booted to a shell that looked finished. Then the self-test ran and found:
#
#   find       missing  ->  "files restored 0", which reads as a failed restore
#   poweroff   missing  ->  a kernel panic on shutdown, which reads as a broken operating system
#   mkdir rm   missing  ->  the system could not create or remove a file
#   cp mv ln   missing  ->  nor copy or move one
#
# **A shell that starts is not a system that works.** Every one of those gaps was invisible until
# something called the command, and an unbundled applet looks exactly like a working one until then.
TOOLS="sh ls cat mount umount uname df dmesg grep sed head tail awk cut printf sleep wc tr sort clear ps free nproc find du tar gzip mkdir rmdir rm cp mv ln date id whoami echo true false poweroff reboot halt"
EXTRA="git tar gzip"

libs=""
# ---------------------------------------------------------------------------------------------
# BusyBox, measured rather than argued.
#
# `mkinitramfs.sh` says, in its own words: *"Without BusyBox, each tool carries its own libraries.
# Six ordinary commands pull in a dozen shared objects between them -- which is the exact pressure
# that makes Fedora 3,180 packages. BusyBox exists to remove it."*
#
# **And then it installs 26 of the host's separate binaries and the 17 libraries behind them.**
# Measured on that build: /bin 11 MB, libraries 8.8 MB, 19.8 MB total -- including libsystemd 1.3 MB
# and libmpfr + libgmp 1.46 MB, which are there only to serve the host's `ps` and `awk`.
#
# BusyBox from Fedora is one 1.4 MB static binary with 394 applets and **zero** library
# dependencies. It covers every tool in the list below.
BB=""
for c in /tmp/bb/usr/bin/busybox "$(command -v busybox 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && BB="$c" && break
done

if [ -n "$BB" ]; then
  install -Dm755 "$BB" "$R/bin/busybox"
  for t in $TOOLS tar gzip; do ln -sf busybox "$R/bin/$t"; done
  # Bash is dropped. BusyBox ash is POSIX and the init uses nothing beyond POSIX -- but the init was
  # written against bash, so if it breaks, that is the first thing to look at.
  rm -f "$R/bin/bash" "$R/bin/sh" 2>/dev/null
  ln -sf busybox "$R/bin/sh"
  printf '  using BusyBox: %s (static, %s applets)\n' "$("$BB" 2>&1 | head -1 | cut -c1-40)" "$("$BB" --list | wc -l)"
else
  # No BusyBox available. Fall back to the host's binaries and carry their closure, which is what
  # the original script does -- and which is 19.8 MB for the same twenty-three commands.
  printf '  no BusyBox found -- falling back to the host binaries and their libraries\n'
  for t in $TOOLS; do
    path="$(command -v "$t" 2>/dev/null)" || continue
    [ -f "$path" ] || continue
    install -Dm755 "$path" "$R/bin/$(basename "$path")" 2>/dev/null
    while IFS= read -r lib; do
      [ -f "$lib" ] || continue
      install -Dm755 "$lib" "$R$lib" 2>/dev/null
      libs="$libs$lib"$'\n'
    done < <(ldd "$path" 2>/dev/null | grep -oE '/[^ ]+')
  done
fi

# git is the one thing BusyBox cannot cover, so its closure is carried regardless.
for t in $EXTRA; do
  [ "$t" = git ] || continue
  path="$(command -v git)" || continue
  install -Dm755 "$path" "$R/bin/git"
  while IFS= read -r lib; do
    [ -f "$lib" ] || continue
    install -Dm755 "$lib" "$R$lib" 2>/dev/null
    libs="$libs$lib"$'\n'
  done < <(ldd "$path" 2>/dev/null | grep -oE '/[^ ]+')
done

# git dispatches on `argv[0]`, so its ~150 entry points in `git --exec-path` are **the same program
# under different names**. On Fedora they are hardlinks to a single 5 MB binary.
#
# **The first version of this script copied them.** 150 x 5 MB = 750 MB of one program, which took
# the rootfs from about 80 MB to 789 MB and drove the initramfs past 300 MB before it was stopped
# and measured. Symlinks cost nothing and behave identically -- git reads argv[0], not the inode.
GITCORE="$(git --exec-path)"
mkdir -p "$R$GITCORE"
for h in "$GITCORE"/*; do
  [ -e "$h" ] && ln -sf /bin/git "$R$GITCORE/$(basename "$h")"
done

# ---------------------------------------------------------------------------------------------
# Strip. Debug and symbol sections are not needed to run a program, and on a distribution that
# ships them they are most of the file. Measured before and after, and printed either way.
strip_dir() {
  local d="$1" before after
  [ -d "$d" ] || return
  before=$(du -sb "$d" 2>/dev/null | cut -f1)
  find "$d" -type f 2>/dev/null | while read -r f; do
    strip --strip-unneeded "$f" 2>/dev/null
  done
  after=$(du -sb "$d" 2>/dev/null | cut -f1)
  printf '    %-28s %8s -> %8s  (-%s)\n' "$(basename "$d")" \
    "$(numfmt --to=iec "$before" 2>/dev/null || echo "$before")" \
    "$(numfmt --to=iec "$after" 2>/dev/null || echo "$after")" \
    "$(numfmt --to=iec "$((before - after))" 2>/dev/null || echo "$((before - after))")"
}
printf '\n  strip:\n'
strip_dir "$R/bin"
for d in "$R"/lib64 "$R"/usr/lib64 "$R"/lib "$R"/usr/lib; do strip_dir "$d"; done

missing=""
for t in $TOOLS $EXTRA; do [ -x "$R/bin/$t" ] || missing="$missing $t"; done
[ -n "$missing" ] && printf '  NOT PACKED:%s\n' "$missing"

# The archive, as files. Not compressed again -- the bundles are already compressed, and a
# browsable archive is worth more than a few megabytes on a drive nobody is short of space on.
mkdir -p "$R/archive"
cp -a "$ARCHIVE"/repos "$ARCHIVE"/worktrees "$ARCHIVE"/INDEX.md "$ARCHIVE"/SHA256SUMS "$R/archive/" 2>/dev/null
printf 'git-version %s\n' "$(git --version | awk '{print $3}')" > "$R/archive/PROVENANCE"

UNIQUE_LIBS="$(printf '%s' "$libs" | sort -u | grep -c . )"

# ---------------------------------------------------------------------------------------------
# init. Reports what it finds rather than what it expects -- including the framebuffer, which is
# the one thing about this operating system that was never verified.
cat > "$R/init" <<'INIT'
#!/bin/sh
export PATH=/bin

mount -t proc     none /proc || echo "  warn: /proc did not mount"
mount -t sysfs    none /sys  || echo "  warn: /sys did not mount"
mount -t devtmpfs none /dev  || mount -t tmpfs none /dev || echo "  warn: /dev did not mount"

clear 2>/dev/null || true

printf '\n'
printf '  \033[1mAshee OS\033[0m  --  test image with archive\n'
printf '  kernel      %s\n' "$(uname -r)"
printf '  memory      %s MB\n' "$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo)"
printf '  tools       %s in /bin\n' "$(ls /bin | wc -l)"
printf '  git         %s\n' "$(head -1 /archive/PROVENANCE 2>/dev/null | cut -d' ' -f2 || echo absent)"
printf '\n'

# The display, reported as TWO interfaces rather than one verdict.
#
# **The first version of this check tested `/proc/fb` and concluded "nothing can be drawn".** On a
# UEFI boot the kernel had logged `fb0: simpledrmdrmfb frame buffer device` and `/dev/dri/card0`
# existed -- so the OS reported a confident negative about a display that was there, using an
# interface it had not looked at.
#
# `/proc/fb` and `/dev/fb0` are the LEGACY fbdev interface. `/dev/dri/card0` is DRM/KMS. They are
# different APIs and one can exist without the other; `simpledrm` is a DRM driver, so the fbdev node
# is the compatibility layer and may or may not appear. **Reporting them separately means the output
# says what is true instead of what a single test concluded.**
printf '  display\n'
if [ -s /proc/fb ]; then
  printf '    fbdev      /proc/fb present\n'
  sed 's/^/               /' /proc/fb
else
  printf '    fbdev      /proc/fb absent -- the legacy interface is not registered\n'
fi
if [ -e /dev/fb0 ]; then
  printf '    /dev/fb0   present\n'
else
  printf '    /dev/fb0   absent -- a mapper that opens this cannot open anything\n'
fi
if [ -e /dev/dri/card0 ]; then
  printf '    DRM        /dev/dri/card0 PRESENT -- this is the interface that exists\n'
else
  printf '    DRM        /dev/dri/card0 absent\n'
fi
printf '\n'

printf '  archive     %s\n' /archive
printf '    bundles   %s\n' "$(ls /archive/repos/*.bundle 2>/dev/null | wc -l)"
printf '    worktrees %s\n' "$(ls /archive/worktrees/*.tar.gz 2>/dev/null | wc -l)"
printf '\n'
printf '  to restore one:\n'
printf '    cd /tmp && git clone /archive/repos/<name>.bundle <name>\n'
printf '  to verify the archive:\n'
printf '    cd /archive && sha256sum -c SHA256SUMS\n'
printf '\n'
exec /bin/sh
INIT
chmod 0755 "$R/init"

# **This line is why the ninth build panicked.**
#
# It read `ln -sf bash "$R/bin/sh"` -- correct while the image carried bash, and unchanged when the
# BusyBox switch removed it. `/bin/sh` became a symlink to a program that no longer existed, so the
# kernel read init's `#!/bin/sh`, could not resolve the interpreter, and reported
# `Failed to execute /init (error -2)` -- ENOENT, with no mention of the shell it was looking for.
#
# **The build had already said so.** `NOT PACKED: bash` was printed by the missing-tool check above,
# and it was read past. The check was right and the person reading it was not.
if [ -n "$BB" ]; then
  ln -sf busybox "$R/bin/sh"
else
  ln -sf bash "$R/bin/sh"
fi

# ---------------------------------------------------------------------------------------------
# the initramfs
( cd "$R" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$OUT/initramfs.gz"

# ---------------------------------------------------------------------------------------------
# the bootable image. grub2-mkrescue produces a hybrid ISO: BIOS and UEFI both, and it can be
# written straight to a drive with dd.
ISO="$OUT/iso"
mkdir -p "$ISO/boot/grub"
cp "$KERNEL" "$ISO/boot/vmlinuz"
cp "$OUT/initramfs.gz" "$ISO/boot/initramfs.gz"
cat > "$ISO/boot/grub/grub.cfg" <<'GRUB'
set timeout=8
set default=0

menuentry "Ashee OS -- test image with archive (serial console)" {
  linux /boot/vmlinuz console=tty0 console=ttyS0 rdinit=/init
  initrd /boot/initramfs.gz
}

menuentry "Ashee OS -- quiet, display only" {
  linux /boot/vmlinuz console=tty0 rdinit=/init quiet
  initrd /boot/initramfs.gz
}
GRUB

grub2-mkrescue -o "$OUT/ashee-test.iso" "$ISO" >/dev/null 2>&1
rc=$?

printf '\n  built %s\n' "$OUT/ashee-test.iso"
printf '    iso           : %s\n' "$(du -h "$OUT/ashee-test.iso" 2>/dev/null | cut -f1)"
printf '    initramfs     : %s\n' "$(du -h "$OUT/initramfs.gz" 2>/dev/null | cut -f1)"
printf '    unpacked root : %s\n' "$(du -sh "$R" 2>/dev/null | cut -f1)"
printf '    shared libs   : %s unique\n' "$UNIQUE_LIBS"
printf '    grub2-mkrescue: exit %s\n' "$rc"
if [ "$rc" -ne 0 ]; then
  printf '\n  the iso was not made -- the image is still bootable directly:\n'
  printf '    qemu-system-x86_64 -enable-kvm -m 512 -kernel %s -initrd %s \\\n' "$KERNEL" "$OUT/initramfs.gz"
  printf '      -append "console=tty0 console=ttyS0 rdinit=/init" -serial stdio\n'
fi
printf '\n  to write it to a drive (DESTROYS THE DRIVE, check the name twice):\n'
printf '    sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n\n' "$OUT/ashee-test.iso"
