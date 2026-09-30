<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# Blocks and the BAM

Below the filesystem is a flat array of 256-byte blocks. `readSector` and
`writeSector` address it as the drive's block commands do; the BAM calls say
what is free.

## Geometry

Constant bit rate on a constant-speed spindle: outer tracks hold more sectors.

| Tracks | Sectors each | Blocks |
|---|---:|---:|
| 1-17 | 21 | 357 |
| 18-24 | 19 | 133 |
| 25-30 | 18 | 108 |
| 31-35 | 17 | 85 |
| 36-40 | 17 | 85 |
| 41-42 | 17 | 34 |

Blocks are stored in track order, then sector order.

```jennifer
import "@mplx/d64/" as d64;

d64.sectorsPerTrack(1);     # 21
d64.sectorsPerTrack(18);    # 19
d64.totalSectors(35);       # 683
d64.sectorOffset(1, 0);     # 0
d64.sectorOffset(18, 0);    # 91392 - the BAM
```

## Blocks

```jennifer
def bam as bytes init d64.readSector($img, 18, 0);
$bam[2];                                  # $41, DOS version byte

def block as bytes init d64.readSector($img, 1, 0);
$block[0] = 0xc7;
$img = d64.writeSector($img, 1, 0, $block);
```

`readSector` returns exactly 256 bytes; `writeSector` requires exactly 256.
Both check the address against the image's geometry - and **neither consults
the BAM**. A free block, an allocated block and a block no directory entry
points at all read and write alike.

## Block ranges

Blocks are contiguous in the image, so a run can be addressed as one.

```jennifer
def run as bytes init d64.readBlocks($img, d64.Link{track: 18, sector: 0}, 2);
len($run);   # 512 - the BAM and the first directory block

$img = d64.writeBlocks($img, d64.Link{track: 1, sector: 0}, $run);
```

A run continues past the last sector of a track at sector 0 of the next one,
and raises if it reaches past the last block of the image. `writeBlocks` takes
a whole multiple of 256 bytes.

Like the single-block calls these ignore the BAM entirely: `writeBlocks` will
overwrite a file's blocks without complaint. Pair them with `allocateSector`
when the blocks are meant to stay claimed.

Blocks also have a flat number, which is what a range walks:

```jennifer
d64.blockNumber(1, 0);     # 0
d64.blockNumber(18, 0);    # 357 - the BAM
d64.blockLink(357);        # Link{track: 18, sector: 0}
```

Dumping a whole image through the range API round-trips:

```jennifer
def all as bytes init d64.readBlocks($img, d64.Link{track: 1, sector: 0},
    d64.blockCount($img));
# equal to d64.toBytes($img) on an image with no error table
```

## The BAM

Four bytes per track: a free-sector count, then a 24-bit map where a **set bit
means free**. `blocksFree` sums the counts, excluding track 18.

```jennifer
d64.blocksFree($img);              # 664 on a fresh 35-track disk
d64.trackBlocksFree($img, 1);      # 21
d64.trackBlocksFree($img, 18);     # 17 of 19
d64.isFree($img, 17, 0);           # true
d64.isAllocated($img, 18, 0);      # true
```

```jennifer
$img = d64.allocateSector($img, 1, 0);
$img = d64.freeSector($img, 1, 0);
```

Both move the bit and fix the count. Both raise when the block is already in
the requested state: a double allocate means two chains share a block, a
double free means count and bitmap have drifted.

A track with no BAM entry - 36-42 under `Cbm`, 41-42 under every layout -
reports "not free" and refuses allocation. See
[Formatting a disk](format.md).

## The allocator

```jennifer
def first as d64.Link init d64.nextFreeSector($img,
    d64.Link{track: 0, sector: 0}, d64.FILE_INTERLEAVE);
# 17/0 on a fresh disk

def next as d64.Link init d64.nextFreeSector($img, $first, d64.FILE_INTERLEAVE);
# 17/10
```

**Interleave.** Within a track the search steps `interleave` sectors - 10 for
files, 3 for directory blocks - so the next block reaches the head just after
the drive has processed the previous one. When the step does not cover the
track (interleave 10 shares a factor with 18 sectors) a linear sweep picks up
the rest, so any track with a free block yields one.

**Spiral.** A full track moves the search outward from track 18: 17, 19, 16,
20, 15, 21, … Track 18 never appears.

```jennifer
d64.trackSearchOrder($img, 0);    # [17, 19, 16, 20, 15, 21, ...]
d64.trackSearchOrder($img, 30);   # [30, 17, 19, 16, ...]
```

`nextFreeSector` raises when nothing is left - the disk-full error
`writeFile` reports.

## Outside the filesystem

Claim a block and write to it; the directory never learns of it.

```jennifer
$img = d64.allocateSector($img, 1, 0);
def block as bytes init d64.readSector($img, 1, 0);
$block[0] = 0xc7;
$block[1] = 0x00;
$img = d64.writeSector($img, 1, 0, $block);
```

The BAM keeps the filesystem off the block; `readSector` gets it back. Tracks
41 and 42 have no BAM entry under any layout, so nothing lands there by
accident.
