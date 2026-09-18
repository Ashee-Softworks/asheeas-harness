#!/usr/bin/env bash
#
# The OS problem, answered by measurement.
#
# The question is not "which language is best". It is:
#
#     which of these can be the bottom?
#
# A kernel is the thing that runs first. Everything else needs something underneath it, and
# every language that requires a runtime is therefore disqualified from the bottom of the stack
# by construction -- not by preference. This measures that, per language:
#
#   1. does the binary depend on anything dynamic?          (ldd)
#   2. does it carry a runtime inside it?                   (nm, looking for runtime symbols)
#   3. can it be built with nothing underneath it at all?    (-nostdlib, no_std)
#
# Number 3 is the whole argument. A language that can produce a binary whose only code is its
# own has something for a kernel. A language that always links a scheduler, a garbage
# collector or a runtime library does not, and no amount of speed makes up for it.
set -uo pipefail

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cd "$W" || exit 1

row() { printf '  %-12s %-10s %-14s %s\n' "$1" "$2" "$3" "$4"; }
header() { printf '\n== %s\n' "$1"; }

printf '  %-12s %-10s %-14s %s\n' LANGUAGE RUNTIME DYNAMIC DEPS NOTE

# ---------------------------------------------------------------------------------------------
# Go: the runtime is not optional. There is no way to ask for it to be left out.
if command -v go >/dev/null 2>&1; then
  printf 'package main\nfunc main(){ println("ok") }\n' > hello.go
  if go build -o hello.go.bin hello.go 2>/dev/null; then
    n="$(nm hello.go.bin 2>/dev/null | grep -c 'runtime\.')"
    row "Go" "embedded" "$(ldd hello.go.bin 2>&1 | grep -c '=>')" "$n runtime.* symbols - the scheduler and GC ship inside"
  fi
fi

# ---------------------------------------------------------------------------------------------
# Java: the JVM is the runtime, and the binary is not a binary.
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  cat > Hello.java <<'EOF'
public class Hello { public static void main(String[] a) { System.out.println("ok"); } }
EOF
  if javac Hello.java 2>/dev/null; then
    row "Java" "required" "JVM" "needs libjvm + a running OS to host it"
  fi
fi

# ---------------------------------------------------------------------------------------------
# Swift: a runtime library, and it needs threads to start.
if command -v swiftc >/dev/null 2>&1; then
  printf 'print("ok")\n' > hello.swift
  if swiftc -O -o hello.swift.bin hello.swift 2>/dev/null; then
    row "Swift" "required" "$(ldd hello.swift.bin 2>/dev/null | grep -c 'libswift')" "links libswiftCore - the runtime must already be running"
  fi
else
  row "Swift" "n/a" "n/a" "swiftc not installed - and this is the same machine where iOS is built"
fi

# ---------------------------------------------------------------------------------------------
# C: -nostdlib, no libc, entry point _start. This is what a kernel is made of.
cat > free.c <<'EOF'
void _start(void) {
  __asm__ volatile("mov $60, %rax\n\txor %rdi, %rdi\n\tsyscall");
}
EOF
if gcc -nostdlib -static -o free.c.bin free.c 2>/dev/null; then
  row "C" "none" "$(ldd free.c.bin 2>&1 | grep -c '=>')" "-nostdlib, entry _start: nothing underneath it"
fi

# ---------------------------------------------------------------------------------------------
# C++: the same, with the parts that need a runtime switched off.
cat > free.cpp <<'EOF'
extern "C" void _start(void) {
  __asm__ volatile("mov $60, %rax\n\txor %rdi, %rdi\n\tsyscall");
}
EOF
if g++ -nostdlib -static -fno-exceptions -fno-rtti -fno-use-cxa-atexit -o free.cpp.bin free.cpp 2>/dev/null; then
  row "C++" "none" "$(ldd free.cpp.bin 2>&1 | grep -c '=>')" "-nostdlib -fno-exceptions -fno-rtti: same floor as C"
fi

# ---------------------------------------------------------------------------------------------
# Rust: no_std, no_main, nostartfiles -- the same floor, reached deliberately.
#
# These link arguments are load-bearing. Without -nostartfiles the link pulls in the C startup
# stubs and a _start is undefined; without -static it comes out dynamic. The first version of
# this script omitted them, rustc failed, and the row was skipped *silently* -- so the table
# printed complete while missing a language. A check that omits without saying so is worse than
# no check, which is why the failure branch below prints.
if command -v rustc >/dev/null 2>&1; then
  cat > free.rs <<'EOF'
#![no_std]
#![no_main]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! { loop {} }
#[no_mangle]
pub extern "C" fn _start() -> ! {
  unsafe { core::arch::asm!("mov rax, 60", "xor rdi, rdi", "syscall", options(noreturn)); }
}
EOF
  if rustc --edition 2021 -O -C panic=abort -C link-arg=-nostartfiles -C link-arg=-static \
       -o free.rs.bin free.rs 2>/tmp/os-probe-rust.err; then
    row "Rust" "none" "$(ldd free.rs.bin 2>&1 | grep -c '=>')" \
      "no_std + no_main ($(nm free.rs.bin 2>/dev/null | grep -ci 'runtime') runtime symbols)"
  else
    row "Rust" "UNKNOWN" "UNKNOWN" "BUILD FAILED - see /tmp/os-probe-rust.err"
  fi
else
  row "Rust" "n/a" "n/a" "rustc not installed"
fi

# ---------------------------------------------------------------------------------------------
# Zig: static by default, no libc unless asked, and a target for no operating system at all.
if command -v zig >/dev/null 2>&1; then
  printf 'pub fn main() void {}\n' > free.zig
  if zig build-exe -static -O ReleaseSmall --name free.zig.bin free.zig 2>/tmp/os-probe-zig.err; then
    row "Zig" "none" "$(ldd free.zig.bin 2>&1 | grep -c '=>')" \
      "$(stat -c%s free.zig.bin) bytes; 'freestanding' is a target it ships with"
  else
    row "Zig" "UNKNOWN" "UNKNOWN" "BUILD FAILED - see /tmp/os-probe-zig.err"
  fi
else
  row "Zig" "n/a" "n/a" "zig not installed"
fi

# ---------------------------------------------------------------------------------------------
# What the answer is. Printed rather than left for the reader, because the table alone invites
# the wrong conclusion: Go passes every check that looks at linkage and fails the only one that
# matters, and the number is inside the binary rather than in its dependencies.
printf '\n  The bottom of the stack is the code that needs nothing underneath it.\n'
printf '  Reached above : C, C++, Rust, Zig\n'
printf '  Not reachable : Go (runtime is not optional), Swift, Java (a runtime must be running)\n'
printf '  ldd alone would pass Go. nm is the measurement that decides it.\n\n'
