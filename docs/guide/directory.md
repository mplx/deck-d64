<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# The directory

A chain of blocks on track 18 from 18/1, each linked by its first two bytes.
Eight 32-byte slots per block, 18 blocks per track: **144 files maximum**.

## Listing

`directoryText` renders `LOAD"$",8`:

```jennifer
use io;
import "@mplx/d64/" as d64;

io.printf("%s", d64.directoryText($img));
```

```
0 "sample disk     " 01 2a
   1 "hello"             prg<
   1 "readme"            seq
   1 "notes"             seq
   1 "scores"            usr
660 blocks free.
```

Header: disk name padded to 16, ID, DOS type. Per file: blocks, quoted name,
leading `*` if never closed, type, trailing `<` if locked. Footer: free
blocks.

Names appear in the lower-case PETSCII spelling - the same bytes a C64 shows
upper case. See [PETSCII](petscii.md).

## Entries

```jennifer
for (def e in d64.listFiles($img)) {
    io.printf("%s %s %d blocks at %d/%d\n",
        $e.name, d64.fileTypeName($e.kind), $e.blocks, $e.track, $e.sector);
}
```

| Field | Meaning |
|---|---|
| `name` | filename, pad bytes trimmed |
| `kind` | `FileType`: `Del`, `Seq`, `Prg`, `Usr`, `Rel` |
| `closed` | false = "splat" file the drive never closed |
| `locked` | true = `SCRATCH` refuses it, listed `<` |
| `track`, `sector` | first block |
| `blocks` | length in blocks |
| `recordLength` | REL only |
| `slot` | position in the chain, 0-based |

Scratched slots are excluded. A scratch zeroes the type byte only - name and
block pointer survive until the slot is reused, so the filter is on the type
byte alone.

## DEL entries are slots, not files

A listed `Del` entry is not a deleted file. Scene disks use them to draw a
border in the listing, with a first-block pointer left at whatever was there,
often the BAM. So:

- `readFile` refuses a DEL entry. Following its pointer would return the
  blocks it happens to name as if they were the file.
- `deleteFile` removes the slot and frees nothing, because a DEL entry owns no
  blocks. That is how border art is removed safely.
- `fileInfo` reports an empty chain for one.

`readChain(img, track, sector)` still reads blocks directly if you want what a
particular pointer names.

A *scratched* slot is different: its type byte is `$00` and it is not listed
at all.

## Reading a listing in the other character set

```jennifer
io.printf("%s", d64.directoryTextIn($img, d64.Charset.Unshifted));
```

Same bytes, the other reading. See [PETSCII](petscii.md).

## Finding

```jennifer
d64.hasFile($img, "HELLO");        # exact name, case-insensitive
d64.findFile($img, "hello");       # raises on a miss

d64.findFiles($img, "*");          # every file
d64.findFiles($img, "he*");        # prefix
d64.findFiles($img, "h?llo");      # ? is one character
```

`*` matches the rest of the name and ends the pattern. `findFiles` returns an
empty list on no match.

## Rename and lock

```jennifer
$img = d64.renameFile($img, "notes", "notes v2");
$img = d64.lockFile($img, "hello");
$img = d64.unlockFile($img, "hello");
```

Rename rewrites the slot only - chain, length and type are untouched. It
refuses a name already present (renaming to the same name is allowed) and a
name over 16 PETSCII characters.

`deleteFile` refuses a locked file.

## Chain growth

One block on a fresh disk. The ninth file takes another block on track 18 at
interleave 3, so the chain runs 18/1, 18/4, 18/7.

```jennifer
len(d64.directorySectors($img));   # 1 fresh, 2 after nine files
```

A slot freed by a scratch is reused before the chain grows. When all 144 slots
are taken, `writeFile` raises a full-directory error, distinct from disk-full.

`directorySectors` raises on a chain that leaves track 18 or loops.
