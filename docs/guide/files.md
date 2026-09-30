<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# Reading and writing files

A file is a linked list of blocks. Bytes `$00`-`$01` point at the next block.
In the last block the track byte is `0` and the sector byte is the length: `n`
means bytes `$02`-`$n` are file data, so `n - 1` payload bytes. Every other
block carries its full 254.

## Writing

```jennifer
use io;
import "@mplx/d64/" as d64;

def img as d64.Image init d64.formatDisk("work disk", "wd");

$img = d64.writeFile($img, "blob", d64.FileType.Prg, $bytes);
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\nworld\n");
$img = d64.writeProgram($img, "demo", 0x0801, $code);
```

| Function | Stores |
|---|---|
| `writeFile` | raw bytes |
| `writeText` | PETSCII; `\n` becomes the CBM carriage return `$0d` |
| `writeProgram` | two-byte load address, low byte first, then the data; type PRG |

Blocks come off the allocator at interleave 10 and are chained as taken; the
directory slot is claimed last, extending the chain if needed. Name and size
checks run before the first block is touched, and value semantics mean a
failure leaves the argument `Image` intact.

Refused: a name already present, `FileType.Rel` (needs a side-sector index
this deck does not build), `FileType.Del`.

### Sizes

An empty file costs one block - the block recording "no bytes used". 254 bytes
is one block, 255 is two.

## Reading

```jennifer
def raw as bytes init d64.readFile($img, "blob");
def text as string init d64.readText($img, "readme");
def prg as d64.Program init d64.readProgram($img, "demo");

$prg.address;   # 2049
$prg.data;      # after the load address
```

`readFile` transcodes nothing: a PRG keeps its load address, a SEQ its exact
bytes. `readText` and `readProgram` are layers over it.

A DEL entry is refused: it is a directory slot rather than a file. See
[the directory](directory.md).

Chain walking is bounded by the disk size, so a self-linking chain raises. A
last block with length byte `0` raises.

### The chain

```jennifer
def e as d64.Entry init d64.findFile($img, "demo");
for (def link in d64.chainOf($img, $e.track, $e.sector)) {
    io.printf("%d/%d ", $link.track, $link.sector);
}
# 17/0 17/10 17/20
```

`readChain(img, track, sector)` reads a chain no entry points at - recovery
for a scratched file whose blocks are not yet reused.

## Metadata

`fileInfo` gathers the directory entry and the chain in one value, so what the
entry claims and what the disk actually holds can be compared.

```jennifer
def info as d64.FileInfo init d64.fileInfo($img, "demo");

$info.entry.name;      # "demo"
$info.entry.kind;      # FileType.Prg
$info.entry.blocks;    # what the directory records
$info.blocks;          # blocks actually chained
$info.blocksMatch;     # whether those two agree
$info.size;            # payload bytes
$info.lastUsed;        # payload bytes in the last block
$info.loadAddress;     # 2049 for a PRG, -1 otherwise
$info.chain;           # list of Link, first to last
```

It reads the chain and the first and last blocks - not the file. `blocksMatch`
is the cheap corruption check: a directory entry claiming a length the chain
does not back up.

`listFileInfo(img)` does the same for every file, in directory order.

```jennifer
for (def i in d64.listFileInfo($img)) {
    io.printf("%s %d blocks %d bytes\n", $i.entry.name, $i.blocks, $i.size);
}
```

## Replacing

```jennifer
$img = d64.updateFile($img, "blob", d64.FileType.Prg, $newBytes);
```

Scratches the old copy, returning its blocks to the BAM, then writes the new
one - which may land on those blocks. Writes the file if absent. Can change
the type.

Not a transaction: on failure the argument `Image` is intact, but the
intermediate state is not recoverable.

## Scratching

```jennifer
$img = d64.deleteFile($img, "blob");
```

Blocks return to the BAM; the slot's type byte is zeroed. Name and block
pointer remain - a scratch is not erasure. Locked files are refused.

## Files on disk

```jennifer
d64.save($img, "work.d64");
def again as d64.Image init d64.open("work.d64");
```

The only two functions touching the filesystem, both wrappers over `toBytes` /
`fromBytes`. Everything else is pure computation, so the deck runs on
`jennifer-tiny`.

```jennifer
def raw as bytes init d64.toBytes($img);      # hand to fs, http, archive
def img as d64.Image init d64.fromBytes($raw);
```
