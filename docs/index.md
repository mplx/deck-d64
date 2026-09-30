<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# @mplx/d64

Read, write, create and format Commodore 1541 D64 disk images.

A D64 is the blocks of a 5.25" floppy stored back to back: 683 blocks of 256
bytes, no header. Inside them is CBM DOS 2.6 - a Block Availability Map in
sector 18/0, a chain of 32-byte directory slots from 18/1, one linked list of
blocks per file. This deck implements all of it in pure Jennifer.

Four BAM layouts: stock 35-track `Cbm`, plus the three 40-track extensions
`SpeedDos`, `DolphinDos` and `PrologicDos`.

## Import

```jennifer
use io;
import "@mplx/d64/" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\n");
io.printf("%s", d64.directoryText($img));
d64.save($img, "sample.d64");
```

The trailing slash resolves to the entry module.

## Value semantics

Every function that changes the disk returns a fresh `Image` and leaves its
argument untouched.

```jennifer
def before as d64.Image init d64.formatDisk("work", "01");
def after as d64.Image init d64.writeText($before, "readme", d64.FileType.Seq, "hi\n");

len(d64.listFiles($before));   # 0
len(d64.listFiles($after));    # 1
```

So the calling shape is `$img = something($img, ...)`. A failed multi-step
operation cannot leave a half-written disk.

## Case

PETSCII `$41`-`$5a` are the unshifted letters, shown upper case on a C64;
ASCII spells the same codes `A`-`Z`. The transcoder swaps case, the `petcat`
convention. **Write names lower case for the classic look.**

```jennifer
d64.toPetscii("hello");   # $48 $45 $4c $4c $4f - "HELLO" on screen
```

`fromPetscii(toPetscii(s)) == s` for anything PETSCII can spell. See
[PETSCII](guide/petscii.md).

## Errors

Every failure is an `Error` with `kind` `"d64"`.

```jennifer
try {
    $img = d64.writeFile($img, "toobig", d64.FileType.Prg, $huge);
} catch (e) {
    io.printf("%s\n", $e.message);
}
```

Raised on: a name over 16 PETSCII characters, a name already present, a full
disk, a full directory, an address outside the image, a scratch of a locked
file, a chain that loops, an image whose length is not a D64 size.

## Contents

| Page | Covers |
|---|---|
| [Formatting a disk](guide/format.md) | `formatDisk`, geometries, the four BAM layouts, error tables |
| [The directory](guide/directory.md) | listing, patterns, rename, lock, chain growth |
| [Reading and writing files](guide/files.md) | block chains, PRG load addresses, replace, scratch |
| [PETSCII](guide/petscii.md) | transcoder, filenames, wildcards |
| [Blocks and the BAM](guide/sectors.md) | raw blocks, allocation, interleave |
| [Drives and computers](reference/hardware.md) | 1540-1581, the machines, GCR and MFM |
| [The D64 format on disk](reference/format.md) | every byte offset |
| [Versioning](internal/versioning.md) | git tags, `VERSION`, CI injection |
| [Cheatsheet](reference/cheatsheet.md) | full API surface |

Runnable programs:
[`examples/`](https://github.com/mplx/deck-d64/tree/main/examples).
