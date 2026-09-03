# apultra

[![License: Zlib](https://img.shields.io/badge/License-Zlib-blue.svg)](https://opensource.org/licenses/Zlib)
[![Language: C99](https://img.shields.io/badge/Language-C99-00599C.svg)](https://en.wikipedia.org/wiki/C99)
[![Assembly: ARM64](https://img.shields.io/badge/Assembly-ARM64%20%2F%20AArch64-red.svg)](asm/ARM64/)
[![Format: aPLib](https://img.shields.io/badge/Format-aPLib%20Compatible-green.svg)](http://ibsensoftware.com/products_aPLib.html)
[![Platform: Cross-Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)]()

> **apultra** is a state-of-the-art, optimal open-source compressor and high-performance decompressor for the **aPLib** format, written in portable C with hand-tuned **ARM64 assembly** acceleration.

---

## Highlights

* **Superior Compression:** Produces files **5% to 7% smaller** on average than `appack` (the original aPLib compressor), beating `gzip -9` while preserving aPLib's tiny depacker footprint.
* **No File Size Limitations:** Compresses arbitrary-sized files (unlike older 64 KB-limited tools like `cap`).
* **100% Format Compatibility:** Decompresses cleanly with any standard aPLib depacker on any target architecture (x86, 68000, Z80, 6502, ARM, etc.).
* **Blazing-Fast Decompression:**
  * Portable C decompressor: **1.2 – 2.1 GB/s** on real-world data, up to **25 GB/s** on repetitive streams.
  * Native ARM64 assembly decompressor (`aplib_arm64.s`): **1.0 – 1.9 GB/s** on real-world code, reaching **43.5 GB/s** on Apple Silicon via 16-byte `ldp`/`stp` chunking and SIMD RLE broadcast.
* **Configurable Speed Modes:** From optimal brute-force parsing to **~7.5x faster** compression with minimal ratio loss (<0.1%).

---

## Compression Ratio

### Reference Benchmark: Linux Kernel (`vmlinux-5.3.0-1-amd64`)

Official comparison from Emmanuel Marty on the full x86_64 kernel image:

| Compressor | Compressed Size | Ratio vs Original | Savings vs `appack` | Depacker Footprint |
| :--- | :---: | :---: | :---: | :---: |
| **Uncompressed** | 27,923,676 B | 100.00% | — | — |
| **`appack`** (official aPLib) | 7,370,129 B | 26.39% | baseline | ~200 bytes |
| **`gzip 1.8 -9`** (Deflate) | 7,166,179 B | 25.66% | -2.77% | ~30+ KB |
| **`apultra`** (Ultra optimal) | **6,910,729 B** | **24.75%** | **-6.23%** | **~200 bytes** |

> [!TIP]
> **Key advantage:** `apultra` produces files **5% to 7% smaller** than the official `appack` and beats `gzip -9`, while retaining aPLib's tiny assembly depacker (**~169–250 bytes** vs ~30+ KB for `zlib`/Deflate).

### Real Measured Benchmarks Across Datasets

Measured directly with `gzip -9` and `apultra` across executable binaries, kernel data, and C source code:

| Dataset / File | Original Size | `gzip -9` | `apultra -faster` (`-1`) | `apultra -fast` (`-f`) | `apultra` (Ultra) | apultra vs `gzip -9` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Kernel Binary (1 MB slice)** | 1,048,576 B | 546,081 B (52.08%) | 497,095 B (47.41%) | 495,133 B (47.22%) | **493,864 B** (47.10%) | **-52,217 B (-9.56%)** |
| **Mach-O ARM64 Executable** | 110,984 B | 43,959 B (39.61%) | 41,087 B (37.02%) | 40,966 B (36.91%) | **40,898 B** (36.85%) | **-3,061 B (-6.96%)** |
| **C Source Code (`shrink.c`)** | 96,737 B | 13,824 B (14.29%) | 13,883 B (14.35%) | 13,875 B (14.34%) | **13,869 B** (14.34%) | +45 B (+0.32%) |
| **C Source Code (`apultra.c`)** | 43,306 B | 6,718 B (15.51%) | 6,831 B (15.77%) | 6,829 B (15.77%) | **6,828 B** (15.77%) | +110 B (+1.64%) |

---

## Compression Speed Modes

`apultra` supports multiple compression profiles via CLI flags and API parameters:

| CLI Flag | API Flag | Arrivals / Pos | Passes | Relative Speed | Size Impact | Best For |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| *(default)* / `-9` | `0` | 62 | 2 | **1.0x** (baseline) | **Optimal** | Release builds, ROMs, demoscene |
| `-f` / `-fast` | `APULTRA_FLAG_FAST` | 9 | 1 | **~5.0x faster** | +0.06% (+8 B / 14 KB) | Fast iterations, CI builds |
| `-ff` / `-faster` / `-1` | `APULTRA_FLAG_FASTER` | 4 | 1 | **~7.5x faster** | +0.10% (+14 B / 14 KB) | Real-time tools, fast packing |

### Benchmark on `src/shrink.c` (96 KB)

```sh
$ apultra -cbench src/shrink.c /dev/null
Ultra (default):  13,869 bytes  |  754 ms  (0.12 MB/s)  |  1.00x baseline

$ apultra -fast -cbench src/shrink.c /dev/null
Fast (-fast):     13,875 bytes  |  158 ms  (0.58 MB/s)  |  4.78x faster  (+6 bytes)

$ apultra -faster -cbench src/shrink.c /dev/null
Faster (-faster): 13,883 bytes  |  101 ms  (0.91 MB/s)  |  7.44x faster  (+14 bytes)
```

---

## Decompression Performance

`apultra` provides two decompressors:
1. **Portable C (`src/expand.c`):** Clean C99 with unaligned 64-bit/128-bit match copies, branch probability hints, and `memset` fast paths.
2. **Native ARM64 Assembly (`asm/ARM64/aplib_arm64.s`):** Hand-optimized for Apple Silicon (M1/M2/M3/M4) and AArch64 systems.

### Features of the ARM64 Decompressor
* **Multi-byte copy engine:** 16-byte pairs (`ldp`/`stp`) and 8-byte quadwords (`ldr`/`str`) for long matches.
* **SIMD Broadcast RLE:** Single-instruction byte duplication into 64-bit/128-bit vector registers for high-speed RLE (`offset == 1`).
* **Branchless tails:** 0..7 byte residue copied via branchless `tbz` instruction cascades.
* **Fast bitstream reader:** Minimized memory accesses with branch-free gamma2 bit decoding.
* **Fully inlined hot paths:** Zero function call/return overhead across token loops.

### Apple Silicon Benchmark

| Test Dataset / File | Uncompressed | Ratio | C (`expand.c`) | ARM64 (`aplib_arm64.s`) |
| :--- | :---: | :---: | :---: | :---: |
| **`divsufsort.c`** | 12.1 KB | 29.8% | 1,204 MB/s | 1,028 MB/s |
| **`apultra.c`** | 41.2 KB | 15.7% | 2,143 MB/s | 1,932 MB/s |
| **`shrink.c`** | 94.3 KB | 14.3% | 2,014 MB/s | 1,865 MB/s |
| **Synthetic (256 KB)** | 256.0 KB | 0.6% | 19,996 MB/s | **27,583 MB/s** |
| **Synthetic RLE (1 MB)** | 1,024.0 KB | 0.1% | 25,815 MB/s | **43,521 MB/s** |

---

## Building

### Prerequisites
* Standard C compiler (`clang`, `gcc`, or MSVC)
* `make` (or Visual Studio on Windows)

### Build with Make (macOS / Linux)

```sh
# Build CLI tool and libapultra.a
make

# Run automated verification suite
./apultra -quicktest
```

### Assembling ARM64 Decompressor

```sh
# macOS (Apple Silicon)
as -arch arm64 asm/ARM64/aplib_arm64.s -o aplib_arm64.o

# Linux AArch64
as asm/ARM64/aplib_arm64.s -o aplib_arm64.o
```

---

## CLI Usage

```text
apultra [-c] [-d] [-v] [-b] [-f|-ff] [-w <size>] [-D <dict>] <infile> <outfile>
```

### Options

| Option | Description |
| :--- | :--- |
| `<infile> <outfile>` | Input file and output destination paths |
| `-d` | Decompress (default: compress) |
| `-c` | Verify compressed stream immediately after compression |
| `-f`, `-fast` | Fast compression mode (~5x faster, 9 arrivals) |
| `-ff`, `-faster`, `-1` | Fastest compression mode (~7.5x faster, 4 arrivals) |
| `-9` | Maximum compression (default optimal mode) |
| `-b` | Backwards compression / decompression |
| `-w <size>` | Maximum window size in bytes (16..2097152, default: 2 MB) |
| `-D <file>` | Use external dictionary file |
| `-stats` | Show detailed compression token breakdown |
| `-v` | Verbose progress and timing information |
| `-cbench` | Benchmark compression in memory |
| `-dbench` | Benchmark decompression in memory |
| `-test` | Run full automated test suite |
| `-quicktest` | Run quick automated test suite |

### Examples

```sh
# Compress with maximum ratio (default)
apultra input.bin output.ap

# Compress with fast mode (~5x faster) and verify
apultra -fast -c input.bin output.ap

# Decompress a file
apultra -d output.ap restored.bin

# In-memory compression benchmark
apultra -cbench input.bin /dev/null
```

---

## Library API

Add `libapultra.h` to your project and link with `libapultra.a`.

### Compression Example

```c
#include <stdio.h>
#include <stdlib.h>
#include "libapultra.h"

void compress_buffer(const unsigned char *src, size_t src_size) {
    size_t max_out = apultra_get_max_compressed_size(src_size);
    unsigned char *dst = malloc(max_out);

    // Pass APULTRA_FLAG_FAST, APULTRA_FLAG_FASTER, or 0 (optimal)
    size_t comp_size = apultra_compress(src, dst, src_size, max_out,
                                        0 /* nFlags */, 0 /* window */, 0 /* dict */,
                                        NULL /* progress */, NULL /* stats */);

    printf("Compressed %zu -> %zu bytes\n", src_size, comp_size);
    free(dst);
}
```

### Decompression Example

#### In C (`src/expand.c`):
```c
#include "libapultra.h"

size_t max_dec = apultra_get_max_decompressed_size(comp_data, comp_size, 0);
unsigned char *out = malloc(max_dec);
size_t orig_size = apultra_decompress(comp_data, out, comp_size, max_dec, 0, 0);
```

#### In ARM64 Assembly (`asm/ARM64/aplib_arm64.s`):
```c
extern size_t apl_decompress(const unsigned char *src, unsigned char *dest);

size_t orig_size = apl_decompress(comp_data, dest_buffer);
```

---

## Projects Using apultra

* [Hyperdrive](https://www.usebox.net/jjm/hyperdrive/) – Shoot'em up for Amstrad CPC 464/6128/GX4000 by usebox.net
* [Brick Rick](https://www.usebox.net/jjm/brick-rick/) – Game for Amstrad CPC 464/6128 by usebox.net ([Polyplay](https://www.polyplay.xyz/navi.php?suche=Brick+Rick&lang=eng))
* [Brick Rick: Graveyard Shift](https://www.usebox.net/jjm/graveyard-shift/) – ZX Spectrum 128K game ([TFW8b.com](https://www.thefuturewas8bit.com/cas019.html))
* [Kitsune's Curse](https://www.usebox.net/jjm/kitsunes-curse/) – Retro title for the CPC line by usebox.net
* [Sgt. Helmet's Training Day](https://www.mojontwins.com/juegos_mojonos/sgt-helmet-training-day-2020-cpc/) – Amstrad CPC game by Mojon Twins (MK1 engine)
* [Prince Dastan - Sokoban Within](https://www.pouet.net/prod.php?which=87382) – CPCRetroDev 2020 game by Euphoria Design
* [Petris](https://github.com/bbbbbr/Petris) – Homebrew game for Nintendo Game Boy
* [Mr Palot](https://github.com/graelx/mrpalot) – ZX Spectrum game (Mojon Twins MK1 engine)
* [rasm](https://github.com/EdouardBERGE/rasm) – Popular Z80 assembler with built-in `apultra` compressed data sections
* [doskrunch](https://github.com/pacnpal/doskrunch) – Multi-tier DOS executable packer and SFX compressor
* [libdragon](https://github.com/DragonMinded/libdragon) – Modern SDK for Nintendo 64 homebrew development

---

## Related Projects & Depackers

* [cap](https://github.com/svendahl/cap) by Sven-Åke Dahl – aPLib compressor for Commodore 64 / 128
* [oapack](https://gitlab.com/eugene77/oapack) by Eugene Larchenko – Brute-force DP packer for aPLib
* [Streamed 8088 decompressor](https://hg.ulukai.org/ecm/inicomp/file/4c6ae7774f3a/apl.asm) by C. Masloch
* [Game Boy decompressor](https://github.com/untoxa/UnaPACK.GBZ80) by untoxa
* [Original aPLib SDK](http://ibsensoftware.com/products_aPLib.html) by Jørgen Ibsen

---

## Inspirations & Credits

* [cap](https://github.com/svendahl/cap) by Sven-Åke Dahl
* [Charles Bloom](http://cbloomrants.blogspot.com/)'s compression blog
* [LZ4](https://github.com/lz4/lz4) by Yann Collet
* **spke** for testing, insights, and support

---

## License

* **apultra** source code is licensed under the [Zlib License](LICENSE).
* The match finder (`matchfinder.c`) is under the **CC0 License** due to portions adapted from Eric Biggers' [wimlib](https://wimlib.net/).
