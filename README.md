apultra -- a new, opensource optimal compressor for the aPLib format
====================================================================

apultra is a command-line tool and a library that compresses bitstreams in the aPLib format. 

The tool produces files that are 5 to 7% smaller on average than appack, the aPLib compressor. Unlike the similar [cap](https://github.com/svendahl/cap) compressor, apultra can compress files larger than 64K.

apultra is written in portable C. It is fully open-source under a liberal license. You can continue to use the regular aPLib decompression libraries for your target environment. You can do whatever you like with it.

    Example compression with vmlinux-5.3.0-1-amd64

    original       27923676 (100,00%)
    appack         7370129 (26,39%)
    gzip 1.8       7166179 (25,66%)
    apultra 1.4.1  6910729 (24,75%)


The output is fully compatible with the original [aPLib](http://ibsensoftware.com/products_aPLib.html) by Jørgen Ibsen.


Decompression Performance
--------------------------

apultra includes both an optimized portable C decompressor (`src/expand.c`) and a highly optimized native **ARM64 assembly decompressor** (`asm/ARM64/aplib_arm64.s`) for Apple Silicon and AArch64 systems.

Features of the ARM64 implementation:
* Multi-byte copy engine: 16-byte pairs (`ldp`/`stp`) and 8-byte transfers (`ldr`/`str`) for long matches
* Broadcasted SIMD engine for high-speed RLE (`offset == 1`)
* Branchless 0..7 byte tail copies
* Streamlined bitstream reader and branch-free gamma2 bit decoding
* Inlined hot paths to minimize call/ret overhead

### Benchmark (Apple Silicon ARM64)

| Dataset / File | Uncompressed | Ratio | C Decompressor | ARM64 Assembly |
| :--- | :---: | :---: | :---: | :---: |
| **`divsufsort.c`** | 12.1 KB | 29.8% | 1,204 MB/s | 1,028 MB/s |
| **`apultra.c`** | 41.2 KB | 15.7% | 2,143 MB/s | 1,932 MB/s |
| **`shrink.c`** | 94.3 KB | 14.3% | 2,014 MB/s | 1,865 MB/s |
| **Synthetic (256 KB)** | 256.0 KB | 0.6% | 19,996 MB/s | **27,583 MB/s** |
| **Synthetic RLE (1 MB)** | 1,024.0 KB | 0.1% | 25,815 MB/s | **43,521 MB/s** |

### Using the ARM64 Decompressor

Function prototype:
```c
size_t apl_decompress(const unsigned char *src, unsigned char *dest);
```
Assembling with GNU `as` or Apple `clang`:
```sh
as -arch arm64 asm/ARM64/aplib_arm64.s -o aplib_arm64.o
```


Compression Levels and Speed Modes
-----------------------------------

`apultra` supports multiple compression trade-offs via CLI flags and library API flags:

| Flag / API | Mode | Arrivals / Pos | Passes | Speed | Ratio Impact |
| :--- | :--- | :---: | :---: | :---: | :---: |
| *(default)* / `-9` | **Ultra** | 62 | 2 | 1.0x (baseline) | **Best possible** |
| `-f` / `-fast` / `APULTRA_FLAG_FAST` | **Fast** | 9 | 1 | **~5x faster** | +0.06% size |
| `-ff` / `-faster` / `-1` / `APULTRA_FLAG_FASTER` | **Fastest** | 4 | 1 | **~7.5x faster** | +0.10% size |

Example usage:
```sh
# Maximum compression (default optimal)
apultra input.bin output.ap

# Fast compression (~5x faster, virtually identical size)
apultra -fast input.bin output.ap

# Fastest compression (~7.5x faster)
apultra -faster input.bin output.ap
```

Inspirations:

 * [cap](https://github.com/svendahl/cap) by Sven-Åke Dahl. 
 * [Charles Bloom](http://cbloomrants.blogspot.com/)'s compression blog. 
 * [LZ4](https://github.com/lz4/lz4) by Yann Collet. 
 * spke for help and support

Some projects that use apultra for compression:
 * [Hyperdrive](https://www.usebox.net/jjm/hyperdrive/), a new, excellent shoot'em up for the Amstrad CPC 464/6128/GX4000, in cartridge format, by usebox.net.
 * [Brick Rick](https://www.usebox.net/jjm/brick-rick/), a new game for the Amstrad CPC 464/6128 by usebox.net. A physical copy can be ordered from [Polyplay](https://www.polyplay.xyz/navi.php?suche=Brick+Rick&lang=eng)
 * [Brick Rick: Graveyard Shift](https://www.usebox.net/jjm/graveyard-shift/), a similar new game for the ZX Spectrum 128K by usebox.net. Get it on tape from [TFW8b.com](https://www.thefuturewas8bit.com/cas019.html)
 * [Kitsune's Curse](https://www.usebox.net/jjm/kitsunes-curse/), another new title for the CPC line by usebox.net.
 * [Sgt. Helmet's Training Day](https://www.mojontwins.com/juegos_mojonos/sgt-helmet-training-day-2020-cpc/), a new game for the Amstrad CPC by the Mojon Twins (using their MK1 engine).
 * [Prince Dastan - Sokoban Within](https://www.pouet.net/prod.php?which=87382), a CPCRetroDev 2020 game for the Amstrad CPC by Euphoria Design 
 * [Petris](https://github.com/bbbbbr/Petris), a homebrew game for the Gameboy.
 * [Mr Palot](https://github.com/graelx/mrpalot), a ZX Spectrum game made with the Mojon Twins MK1 engine.
 * [rasm](https://github.com/EdouardBERGE/rasm), a popular Z80 assembler, features built-in support for apultra-compressed data sections.

Also of interest:
 * [oapack](https://gitlab.com/eugene77/oapack) by Eugene Larchenko, a brute-force (exhaustive) optimal packer for the aPLib format. 
 * [Streamed 8088 decompressor](https://hg.ulukai.org/ecm/inicomp/file/4c6ae7774f3a/apl.asm) for aPLib by C. Masloch
 * [Gameboy decompressor](https://github.com/untoxa/UnaPACK.GBZ80) by untoxa

License:

* The apultra code is available under the Zlib license.
* The match finder (matchfinder.c) is available under the CC0 license due to using portions of code from Eric Bigger's Wimlib in the suffix array-based matchfinder.
