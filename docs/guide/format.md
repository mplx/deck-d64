<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# Formatting a disk

`formatDisk` is `NEW0:NAME,ID` on a 1541: every block free, a blank BAM and
the disk header in 18/0, one empty directory block in 18/1, those two marked
taken.

```jennifer
use io;
import "@mplx/d64/" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");

len(d64.toBytes($img));   # 174848
d64.blocksFree($img);     # 664
d64.diskName($img);       # "sample disk"
d64.diskId($img);         # "01"
d64.dosType($img);        # "2a"
```

664, not 683: track 18 is reserved for the BAM and the directory, so
`blocksFree` excludes it. That is the number the drive prints.

Name: up to 16 characters. ID: exactly 2. Both are PETSCII - write them lower
case.

## Geometries

`formatDiskWith` takes a `FormatOptions`. A zero field takes its default.

```jennifer
def opts as d64.FormatOptions init d64.FormatOptions{
    tracks: 40,
    format: d64.DiskFormat.SpeedDos,
    errorInfo: false,
    dosType: "", fill: 0, mode: d64.FormatMode.Full
};
def img as d64.Image init d64.formatDiskWith($opts, "forty track", "40");

len(d64.toBytes($img));   # 196608
d64.blocksFree($img);     # 749
```

| Tracks | Blocks | Plain | With error table |
|---:|---:|---:|---:|
| 35 | 683 | 174,848 | 175,531 |
| 40 | 768 | 196,608 | 197,376 |
| 42 | 802 | 205,312 | 206,114 |

`imageSize(tracks, errorInfo)` computes these; `tracksForSize(n)` and
`sizeHasErrorInfo(n)` read them back. `fromBytes` derives geometry from length
alone.

## The four BAM layouts

The stock BAM has entries for tracks 1-35 at `$04`-`$8f`, then the disk
header. The 40-track speeder DOSes each put the five extra entries elsewhere.

| `DiskFormat` | Tracks 36-40 | Header |
|---|---|---|
| `Cbm` | *none* | `$90` |
| `SpeedDos` | `$c0`-`$d3` | `$90` |
| `DolphinDos` | `$ac`-`$bf` | `$90` |
| `PrologicDos` | `$90`-`$a3` | `$a4` |

PrologicDOS used the disk-name bytes and moved the header 20 bytes forward.
`headerOffsetFor` and `bamEntryOffset` answer both questions; every BAM call
goes through them.

```jennifer
d64.bamEntryOffset(d64.DiskFormat.SpeedDos, 36);     # 192 ($c0)
d64.bamEntryOffset(d64.DiskFormat.DolphinDos, 36);   # 172 ($ac)
d64.bamEntryOffset(d64.DiskFormat.Cbm, 36);          # -1
```

### 40 tracks in the stock layout

Legal, and a real drive reads it - but tracks 36-40 have no BAM entry, so
nothing is allocated there.

```jennifer
def plain as d64.FormatOptions init d64.FormatOptions{
    tracks: 40, format: d64.DiskFormat.Cbm, errorInfo: false, dosType: "", fill: 0, mode: d64.FormatMode.Full
};
def img as d64.Image init d64.formatDiskWith($plain, "plain forty", "01");

d64.blocksFree($img);          # 664, not 749
d64.hasBamEntry($img, 36);     # false
d64.isFree($img, 36, 0);       # false - unavailable
```

The reverse is refused: a speeder layout on 35 tracks raises.

### Tracks 41 and 42

No layout defines entries for them. `readSector` and `writeSector` reach them;
the allocator never does and `blocksFree` never counts them.

## Detection

`fromBytes` and `open` call `detectFormat`:

- 35 tracks → always `Cbm`;
- DOS type at `$b9` instead of `$a5` → `PrologicDos`;
- otherwise whichever extra region carries plausible free-sector counts.

A heuristic. Override it:

```jennifer
def img as d64.Image init d64.withFormat(d64.open("mystery.d64"),
    d64.DiskFormat.DolphinDos);
```

`withFormat` changes no bytes, only how the BAM is read.

## Error tables

One byte per block after the block data: the read result a mastering tool
recorded. `$01` is no error; other codes are the 1541's own.

```jennifer
def opts as d64.FormatOptions init d64.FormatOptions{
    tracks: 35, format: d64.DiskFormat.Cbm, errorInfo: true, dosType: "", fill: 0, mode: d64.FormatMode.Full
};
def img as d64.Image init d64.formatDiskWith($opts, "protected", "01");

d64.sectorError($img, 18, 0);                    # 1
$img = d64.setSectorError($img, 17, 3, 0x0b);    # data checksum error
$img = d64.clearErrorTable($img);
```

An image without a table reports `ERROR_OK` everywhere; `setSectorError`
raises on one.

## Quick and full

CBM DOS draws the distinction between `N0:NAME,ID` and `N0:NAME`, and so does
this deck.

| | Writes | Leaves | On a 1541 |
|---|---|---|---|
| `reformat` / `FormatMode.Full` | every block, then BAM + directory | nothing | ~1 minute |
| `quickFormat` / `FormatMode.Quick` | BAM + first directory block | every other block | instant |

```jennifer
$img = d64.reformat($img, "fresh", "02");    # full wipe, blocks set to $00
$img = d64.quickFormat($img, "fresh");       # soft format, ID kept
```

A quick format lists the disk as empty and frees every block, but the old
files' bytes are still on it - unreachable, not erased. Use a full format when
that matters.

`quickFormat` keeps the disk ID, because the drive does not re-stamp it
either. Two disks soft-formatted from the same original share an ID, which is
how a real 1541 comes to act on a stale BAM after a swap.

### The fill byte

A full format sets every block to `fill`, `$00` by default.

```jennifer
def opts as d64.FormatOptions init d64.defaultFormatOptions();
$opts.fill = 0xff;
$img = d64.reformatWith($img, $opts, "wiped", "02");

d64.readSector($img, 17, 0)[0];   # 255
```

`fill` works on `formatDiskWith` too, for a new image. The error table is
never filled - it is set to `ERROR_OK` regardless.

`reformatWith` reads only `mode`, `fill` and `dosType` from the options.
Geometry and BAM layout always come from the image: changing those makes a
different disk, which is `formatDiskWith`.
