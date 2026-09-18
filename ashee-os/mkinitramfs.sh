#!/usr/bin/env bash
#
# Ashee OS -- the smallest thing that is genuinely an operating system.
#
# A kernel, an init, and a shell. Nothing else. The point is not that it is small; the point is
# to have a number for "small", on this machine, next to Fedora's:
#
#     Fedora    3,180 packages   20.4 GB   208 modules loaded, 4,842 shipped
#     Ashee OS  a handful         ~megabytes   0 modules shipped
#
# ## What it is built from
#
# The host's own kernel, booted directly. Not rebuilt, not patched -- because the kernel is one
# of the questions that was answered 30 years ago and does not need answering again. What is
# built here is the layer above it, and the build direction is the FFmpeg direction: start
# empty, add what is needed, and stop.
#
# ## The dependency closure, measured rather than argued
#
# Without BusyBox, each tool carries its own libraries. Six ordinary commands pull in a dozen
# shared objects between them -- which is the exact pressure that makes Fedora 3,180 packages.
# BusyBox exists to remove it, and this script prints the closure so the number is visible.
set -uo pipefail

OUT="${1:-/tmp/ashee-os}"
KERNEL="/boot/vmlinuz-$(uname -r)"
[ -f "$KERNEL" ] || { echo "no bootable kernel at $KERNEL" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/root"/{bin,dev,proc,sys,tmp,run}
R="$OUT/root"

# ---------------------------------------------------------------------------------------------
# The tools. Every one of these is a question already answered -- ls, cat, mount, sh -- and not
# one of them is written here.
#
# ## What this list deliberately does NOT carry, and why that is a decision rather than an oversight
#
# `find`, `mkdir`, `rm`, `cp`, `mv`, `tar`, `poweroff` are all absent. **This image therefore cannot
# create a file, copy one, remove one, extract an archive, or shut down cleanly** -- `poweroff`
# missing means PID 1 exits and the kernel panics with "Attempted to kill init".
#
# That was found by *running* it: a self-test asked the image to do a job and every such call
# returned "not found", which reads as a failed operation rather than a missing applet. See
# `mkpendrive.sh`, which carries 49 applets including these and is the image you would actually
# boot.
#
# They are still absent here on purpose. **This script exists to produce one number** -- the
# smallest closure that is genuinely an operating system -- and every applet added changes what that
# number measures. `mkpendrive.sh` is the usable image; this is the measurement. Keeping them in one
# script would have made the number mean nothing.
TOOLS="sh bash ls cat mount umount uname df dmesg grep sed head tail awk cut printf sleep wc tr sort clear ps free nproc"
libs=""
for t in $TOOLS; do
  path="$(command -v "$t" 2>/dev/null)" || continue
  [ -f "$path" ] || continue
  install -Dm755 "$path" "$R/bin/$(basename "$path")"
  while IFS= read -r lib; do
    [ -f "$lib" ] || continue
    install -Dm755 "$lib" "$R$lib" 2>/dev/null
    libs="$libs$lib"$'\n'
  done < <(ldd "$path" 2>/dev/null | grep -oE '/[^ ]+')
done

# Which of them did not make it. Printed, not assumed: the first build omitted `wc` from the
# list above and nothing said so -- the banner simply printed blanks and looked fine.
missing=""
for t in $TOOLS; do [ -x "$R/bin/$t" ] || missing="$missing $t"; done
[ -n "$missing" ] && printf '  NOT PACKED:%s\n' "$missing"

UNIQUE_LIBS="$(printf '%s' "$libs" | sort -u | grep -c . )"

# ---------------------------------------------------------------------------------------------
# init. The first process, and it does three things: mounts the pseudo-filesystems it needs,
# says what it is, and hands over a shell. Anything more would be somebody else's decision.
cat > "$R/init" <<'INIT'
#!/bin/sh
#
# PATH is not inherited from the kernel. Without the line below, every external command is
# "command not found" while the shell's builtins keep working -- so an init that looks alive can
# be doing nothing at all. That is exactly what the first boot of this image did: printf printed
# the banner, uname and awk were reported missing from a /bin they were sitting in, and the
# banner showed blanks that looked like an unfinished feature rather than a failure.
export PATH=/bin

# Errors are NOT suppressed. The first version wrote `2>/dev/null` on each mount, so a mount
# that failed was indistinguishable from one that worked, and the failure above went unseen.
mount -t proc     none /proc || echo "  warn: /proc did not mount"
mount -t sysfs    none /sys  || echo "  warn: /sys did not mount"
mount -t devtmpfs none /dev  || mount -t tmpfs none /dev || echo "  warn: /dev did not mount"

clear 2>/dev/null || true

printf '\n'
printf '  \033[1mAshee OS\033[0m\n'
printf '  kernel      %s\n' "$(uname -r)"
printf '  memory      %s MB\n' "$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo)"
printf '  modules     %s loaded, 0 shipped\n' "$(wc -l < /proc/modules 2>/dev/null || echo 0)"
printf '  processes   %s\n' "$(ls -d /proc/[0-9]* 2>/dev/null | wc -l)"
printf '  tools       %s in /bin\n' "$(ls /bin | wc -l)"
printf '\n'
printf '  Fedora on this machine, for the same machine:\n'
printf '    3,180 packages - 20,400 MB - 208 modules loaded from 4,842 shipped\n'
printf '\n'
printf '  This is a kernel, an init and a shell. Nothing was shipped that was not needed,\n'
printf '  and nothing here was written from scratch.\n'
printf '\n'

exec /bin/sh
INIT
chmod 0755 "$R/init"
ln -sf bash "$R/bin/sh" 2>/dev/null

# ---------------------------------------------------------------------------------------------
# The image. newc is the format the kernel reads it in; gzip because it compresses to nothing.
( cd "$R" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$OUT/ashee-initramfs.gz"

ROOTFS_KB="$(du -sk "$R" | cut -f1)"
IMG_KB="$(du -sk "$OUT/ashee-initramfs.gz" | cut -f1)"

printf '\n  built %s\n' "$OUT/ashee-initramfs.gz"
printf '    unpacked rootfs : %s KB\n' "$ROOTFS_KB"
printf '    compressed image: %s KB\n' "$IMG_KB"
printf '    shared libs     : %s unique (the dependency closure of %s commands)\n' "$UNIQUE_LIBS" "$(printf '%s' "$TOOLS" | wc -w)"
printf '    kernel          : %s (%s KB)\n' "$KERNEL" "$(( $(stat -c%s "$KERNEL") / 1024 ))"
printf '\n  to see it:\n'
printf '    qemu-system-x86_64 -enable-kvm -m 256 -smp 1 \\\n'
printf '      -kernel %s \\\n' "$KERNEL"
printf '      -initrd %s \\\n' "$OUT/ashee-initramfs.gz"
printf '      -append "console=tty0 console=ttyS0 rdinit=/init" -serial file:%s/serial.log\n\n' "$OUT"
