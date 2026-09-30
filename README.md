# @mplx/d64

[![test](https://github.com/mplx/deck-d64/actions/workflows/test.yml/badge.svg)](https://github.com/mplx/deck-d64/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://mplx.github.io/deck-d64/)
[![release](https://img.shields.io/github/v/release/mplx/deck-d64)](https://github.com/mplx/deck-d64/releases/latest)

Read, write, create and format Commodore 1541 **D64 disk images** from
[Jennifer](https://jennifer-lang.dev/).

A D64 is a byte-for-byte copy of a 5.25" floppy: 683 blocks of 256 bytes,
holding CBM DOS 2.6 - a Block Availability Map in sector 18/0, a chain of
32-byte directory slots from 18/1, one linked list of blocks per file. This
deck implements all of it in pure Jennifer: build images for an emulator or a
real drive, inspect or repair existing ones, bulk-extract an archive, without
`c1541`.

**[Read the documentation](https://mplx.github.io/deck-d64/)**

## Usage

```jennifer
use io;
import "@mplx/d64/" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello from jennifer\n");
$img = d64.writeProgram($img, "demo", 0x0801, $code);

io.printf("%s", d64.directoryText($img));
# 0 "sample disk     " 01 2a
#    1 "readme"            seq
#    3 "demo"              prg
# 660 blocks free.

d64.save($img, "sample.d64");
```

## What it does

- **Format** - `formatDisk` is `NEW0:NAME,ID`. `formatDiskWith` takes the
  geometry (35/40/42 tracks, optional error table) and the BAM layout. Full
  format wipes every block to a fill byte; `quickFormat` erases the BAM and
  directory only, as `N0:NAME` does.
- **Four BAM layouts** - stock 35-track, plus the three incompatible 40-track
  extensions: **SpeedDOS**, **DolphinDOS**, **PrologicDOS**. Detected on load,
  overridable.
- **List** - `directoryText` renders `LOAD"$",8`; `listFiles` gives typed
  entries; `findFiles` filters with the drive's `*` and `?` patterns.
- **Read and write** - SEQ, PRG, USR as raw bytes, PETSCII text, or a program
  split at its load address. `updateFile` replaces, `deleteFile` scratches;
  rename and lock.
- **PETSCII** - UTF-8 ↔ PETSCII in the `petcat` convention, exact round trip
  for anything the character set can spell.
- **Metadata** - `fileInfo` returns the directory entry, the block chain, the
  real byte size and the PRG load address, and flags an entry whose recorded
  length the chain does not back up.
- **Edit** - `patchSector` and `patchFile` overwrite bytes in place,
  `readAt` / `writeAt` give a flat byte view, and `findBytes` locates a
  pattern anywhere on the disk.
- **Blocks** - `readSector` / `writeSector` and `readBlocks` / `writeBlocks`
  for runs, all independent of the BAM, plus the BAM calls themselves.

Value-semantic throughout: a mutator returns a fresh `Image` and leaves its
argument alone.

## Install

```sh
jvc add @mplx/d64
```

Or vendor the `src/` subtree by hand from a release archive.

## Requirements

Jennifer 0.25.0 or newer. No network, subprocess or database: the filesystem
is built from `bytes` and bitwise operations, so the deck runs unchanged on
`jennifer-tiny`. Only `open` and `save` touch the disk, through `fs`.

## Development

```sh
tools/version.sh                     # the version the git tags imply
tools/inject-version.sh              # stamp it into src/topics/version.j
jennifer test src/d64_test.j         # the white-box overlay
jennifer lint src/d64.j              # the compilable unit
jennifer fmt -l src examples         # formatting
tools/check-headers.sh               # SPDX + interpreter floor
tools/check-overlays.sh              # every topic has a test
tools/check-docs.sh                  # docs match the code: signatures,
                                     #   docblocks, links, claimed values
tools/check-examples.sh              # every example still runs
tools/pack.sh dist                   # the release archive, as CI builds it
grimoire build                       # the documentation site
```

## Licence

LGPL-3.0-only. Every source file carries the SPDX header, and
`tools/check-headers.sh` keeps those in step with `deck.toml`.
