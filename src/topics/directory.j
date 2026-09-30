# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - the directory: the chain of 32-byte slots on track 18.
# Spliced into d64.j via include - not a standalone module.

/**
 * What kind of file a directory entry describes.
 *
 * `Del` is a scratched slot, `Seq` a stream of bytes, `Prg` a program with a
 * two-byte load address in front of it, `Usr` the same as `Seq` with a name
 * the drive treats as the program's business, and `Rel` a record-oriented
 * file with a side-sector index. The zero value is `Del`.
 */
export def enum FileType {
    Del,
    Seq,
    Prg,
    Usr,
    Rel
};

/**
 * One directory entry.
 *
 * @field {string}   name          the filename, pad bytes trimmed
 * @field {FileType} kind          SEQ, PRG, USR, REL or DEL
 * @field {bool}     closed        false marks a "splat" file the drive never closed
 * @field {bool}     locked        true marks a file `SCRATCH` refuses, shown as `<`
 * @field {int}      track         track of the file's first block
 * @field {int}      sector        sector of the file's first block
 * @field {int}      blocks        length in blocks, as the directory records it
 * @field {int}      recordLength  record length, REL files only
 * @field {int}      slot          position in the directory chain, 0-based
 */
export def struct Entry {
    name as string,
    kind as FileType,
    closed as bool,
    locked as bool,
    track as int,
    sector as int,
    blocks as int,
    recordLength as int,
    slot as int
};

/** Directory slots in one directory block. */
export def const ENTRIES_PER_SECTOR as int init 8;

/** Bytes one directory slot occupies. */
export def const ENTRY_SIZE as int init 32;

/** Slots a stock directory holds: 18 blocks of 8. */
export def const MAX_DIRECTORY_ENTRIES as int init 144;

/**
 * The name of a file type, as a directory listing spells it.
 *
 * @param {FileType} kind the file type
 * @return {string} `"del"`, `"seq"`, `"prg"`, `"usr"` or `"rel"`
 * @example
 *   fileTypeName(FileType.Prg);   # "prg"
 */
export func fileTypeName(kind as FileType) {
    match ($kind) {
        when Del { return "del"; }
        when Seq { return "seq"; }
        when Prg { return "prg"; }
        when Usr { return "usr"; }
        when Rel { return "rel"; }
    }
    return "del";
}

/**
 * The file type a name spells, the inverse of {@link fileTypeName}.
 *
 * @param {string} name the type name, case-insensitive
 * @return {FileType} the file type
 * @throws {Error} when the name is not one of the five
 * @example
 *   fileTypeFromName("PRG");   # FileType.Prg
 */
export func fileTypeFromName(name as string) {
    match (strings.lower(strings.trim($name))) {
        when "del" { return FileType.Del; }
        when "seq" { return FileType.Seq; }
        when "prg" { return FileType.Prg; }
        when "usr" { return FileType.Usr; }
        when "rel" { return FileType.Rel; }
    }
    fail("\"" + $name + "\" is not a CBM file type");
    return FileType.Del;
}

/**
 * The file type the low nibble of a directory type byte encodes.
 *
 * @param {int} raw the type byte
 * @return {FileType} the file type
 * @example
 *   fileTypeFromByte(0x82);   # FileType.Prg
 */
export func fileTypeFromByte(raw as int) {
    match ($raw & 0x0f) {
        when 1 { return FileType.Seq; }
        when 2 { return FileType.Prg; }
        when 3 { return FileType.Usr; }
        when 4 { return FileType.Rel; }
    }
    return FileType.Del;
}

/**
 * The directory type byte for a type and its two flags.
 *
 * Bit 7 is the closed flag - a file without it lists with a leading `*` and
 * is what a drive leaves behind when it is reset mid-write. Bit 6 is the
 * lock, which lists as a trailing `<`.
 *
 * @param {FileType} kind   the file type
 * @param {bool}     closed true for a properly closed file
 * @param {bool}     locked true for a scratch-protected file
 * @return {int} the type byte
 * @example
 *   fileTypeByte(FileType.Prg, true, false);   # $82
 */
export func fileTypeByte(kind as FileType, closed as bool, locked as bool) {
    def raw as int init 0;
    match ($kind) {
        when Del { $raw = 0; }
        when Seq { $raw = 1; }
        when Prg { $raw = 2; }
        when Usr { $raw = 3; }
        when Rel { $raw = 4; }
    }
    if ($closed) {
        $raw = $raw | 0x80;
    }
    if ($locked) {
        $raw = $raw | 0x40;
    }
    return $raw;
}

/**
 * The blocks of the directory chain, in order.
 *
 * The chain starts at 18/1 and each block points at the next through its
 * first two bytes; a track byte of 0 ends it. The walk is bounded by the
 * track length, so a corrupt image that links a block to itself raises
 * rather than spinning.
 *
 * @param {Image} img the image
 * @return {list of Link} the directory blocks
 * @throws {Error} when the chain loops or leaves track 18
 * @example
 *   len(directorySectors(formatDisk("d", "01")));   # 1
 */
export func directorySectors(img as Image) {
    def chain as list of Link;
    def track as int init DIRECTORY_TRACK;
    def sector as int init FIRST_DIRECTORY_SECTOR;
    def guard as int init sectorsPerTrack(DIRECTORY_TRACK);
    while ($track != 0) {
        if ($track != DIRECTORY_TRACK) {
            fail("the directory chain leaves track 18 at " + convert.toString($track) + "/" +
                convert.toString($sector));
        }
        if (len($chain) >= $guard) {
            fail("the directory chain loops - more than " + convert.toString($guard) +
                " blocks on track 18");
        }
        $chain[] = Link{track: $track, sector: $sector};
        def block as bytes init readSector($img, $track, $sector);
        $track = $block[0];
        $sector = $block[1];
    }
    return $chain;
}

/**
 * Every live file on the disk, in directory order.
 *
 * Scratched slots are left out: CBM DOS marks a scratch by zeroing the type
 * byte alone, so the name and the block pointer of a deleted file stay in the
 * slot until something else claims it.
 *
 * @param {Image} img the image
 * @return {list of Entry} the files
 * @example
 *   for (def e in listFiles($img)) { io.printf("%s\n", $e.name); }
 */
export func listFiles(img as Image) {
    def files as list of Entry;
    def slot as int init 0;
    for (def link in directorySectors($img)) {
        def block as bytes init readSector($img, $link.track, $link.sector);
        for (def i as int init 0; $i < ENTRIES_PER_SECTOR; $i = $i + 1) {
            if ($block[$i * ENTRY_SIZE + 2] != 0) {
                $files[] = decodeEntry($block, $i, $slot);
            }
            $slot = $slot + 1;
        }
    }
    return $files;
}

/**
 * The files whose names match a CBM DOS pattern.
 *
 * @param {Image}  img     the image
 * @param {string} pattern the pattern, `*` and `?` recognised
 * @return {list of Entry} the matching files, in directory order
 * @example
 *   findFiles($img, "*");      # every file
 *   findFiles($img, "he*");    # every file whose name starts "he"
 */
export func findFiles(img as Image, pattern as string) {
    def hits as list of Entry;
    for (def e in listFiles($img)) {
        if (matchName($pattern, $e.name)) {
            $hits[] = $e;
        }
    }
    return $hits;
}

/**
 * Whether a file of this name is on the disk.
 *
 * The name is matched exactly, not as a pattern - use {@link findFiles} for
 * that - and case-insensitively.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename
 * @return {bool} true when the file exists
 * @example
 *   hasFile($img, "hello");   # false on a fresh disk
 */
export func hasFile(img as Image, name as string) {
    return findSlot($img, $name) >= 0;
}

/**
 * The directory entry of one file.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename, matched exactly
 * @return {Entry} the entry
 * @throws {Error} when no file of that name is on the disk
 * @example
 *   findFile($img, "hello").blocks;   # how many blocks it takes
 */
export func findFile(img as Image, name as string) {
    def slot as int init findSlot($img, $name);
    if ($slot < 0) {
        fail("no file named \"" + $name + "\" on this disk");
    }
    def link as Link init entryBlockLink($img, $slot);
    return decodeEntry(
        readSector($img, $link.track, $link.sector),
        $slot % ENTRIES_PER_SECTOR,
        $slot);
}

/**
 * The slot one filename occupies, or -1 when the disk has no such file.
 *
 * Decodes each slot's name and nothing else. Going through {@link listFiles}
 * would build a whole `Entry` - nine fields and a decoded string - for every
 * file on the disk just to compare one of them, which is most of the cost of
 * writing a file to a full directory.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename, matched case-insensitively
 * @return {int} the slot index, or -1
 */
func findSlot(img as Image, name as string) {
    def wanted as string init strings.lower($name);
    def slot as int init 0;
    for (def link in directorySectors($img)) {
        def block as bytes init readSector($img, $link.track, $link.sector);
        for (def i as int init 0; $i < ENTRIES_PER_SECTOR; $i = $i + 1) {
            def at as int init $i * ENTRY_SIZE;
            if ($block[$at + 2] != 0 and
                strings.lower(decodeName($block[$at + 5..$at + 5 + MAX_FILENAME])) == $wanted) {
                return $slot;
            }
            $slot = $slot + 1;
        }
    }
    return -1;
}

/**
 * The directory as a 1541 prints it for `LOAD"$",8`.
 *
 * The header line carries the disk name, the ID and the DOS type; one line
 * per file carries its length in blocks, its quoted name, a leading `*` when
 * the file was never closed, its type and a trailing `<` when it is locked;
 * the last line is the free-block count.
 *
 * Names come back in the lower-case spelling this deck writes PETSCII in -
 * a C64 shows the same bytes in upper case.
 *
 * @param {Image} img the image
 * @return {string} the listing, newline-terminated
 * @example
 *   io.printf("%s", directoryText($img));
 */
export func directoryText(img as Image) {
    return directoryTextIn($img, Charset.Shifted);
}

/**
 * The directory as a 1541 prints it, read in a chosen character set.
 *
 * `Charset.Unshifted` is the reading a disk full of border art was drawn for:
 * the codes a shifted reading turns into runs of capitals are box drawing and
 * shades, so the frame appears instead of the letters that share those bytes.
 *
 * @param {Image}   img     the image
 * @param {Charset} charset which character set to read the names in
 * @return {string} the listing, newline-terminated
 * @example
 *   io.printf("%s", directoryTextIn($img, Charset.Unshifted));
 */
export func directoryTextIn(img as Image, charset as Charset) {
    def lines as list of string;
    $lines[] = io.sprintf(
        "0 \"%s\" %s %s",
        io.sprintf("%s|pad=16|align=left", diskNameIn($img, $charset)),
        diskId($img),
        dosType($img));
    def slot as int init 0;
    for (def link in directorySectors($img)) {
        def block as bytes init readSector($img, $link.track, $link.sector);
        for (def i as int init 0; $i < ENTRIES_PER_SECTOR; $i = $i + 1) {
            def at as int init $i * ENTRY_SIZE;
            if ($block[$at + 2] != 0) {
                $lines[] = entryLine(
                    decodeEntry($block, $i, $slot),
                    decodeNameIn($block[$at + 5..$at + 5 + MAX_FILENAME], $charset));
            }
            $slot = $slot + 1;
        }
    }
    $lines[] = io.sprintf("%d blocks free.", blocksFree($img));
    $lines[] = "";
    return strings.join($lines, "\n");
}

/**
 * The 16 raw name bytes of an entry's directory slot.
 *
 * `Entry.name` is already decoded, in the shifted reading, and decoding is
 * lossy for anything PETSCII cannot spell. This is the way to read a name in
 * the other character set without going back through the disk yourself.
 *
 * @param {Image} img   the image
 * @param {Entry} entry the entry, whose `slot` addresses it
 * @return {bytes} 16 PETSCII bytes, pad included
 * @throws {Error} when the slot is past the end of the directory chain
 * @example
 *   decodeNameIn(nameBytes($img, $entry), Charset.Unshifted);
 */
export func nameBytes(img as Image, entry as Entry) {
    def link as Link init entryBlockLink($img, $entry.slot);
    def block as bytes init readSector($img, $link.track, $link.sector);
    def at as int init ($entry.slot % ENTRIES_PER_SECTOR) * ENTRY_SIZE + 5;
    return $block[$at..$at + MAX_FILENAME];
}

/**
 * One file's line of a directory listing.
 *
 * @param {Entry}  entry the file
 * @param {string} name  the filename, already decoded in the caller's charset
 * @return {string} the line, without its newline
 */
func entryLine(entry as Entry, name as string) {
    def splat as string init " ";
    if (not $entry.closed) {
        $splat = "*";
    }
    def lock as string init "";
    if ($entry.locked) {
        $lock = "<";
    }
    def quoted as string init "\"" + $name + "\"";
    return io.sprintf(
        "%s %s %s%s%s",
        io.sprintf("%d|pad=4|align=right", $entry.blocks),
        io.sprintf("%s|pad=18|align=left", $quoted),
        $splat,
        fileTypeName($entry.kind),
        $lock);
}

/**
 * Rename a file.
 *
 * @param {Image}  img     the image
 * @param {string} oldName the file to rename
 * @param {string} newName the name to give it, 1 to 16 characters
 * @return {Image} the image with the entry rewritten
 * @throws {Error} when the file is missing, or the new name is taken or unfit
 * @example
 *   $img = renameFile($img, "hello", "hello v2");
 */
export func renameFile(img as Image, oldName as string, newName as string) {
    def entry as Entry init findFile($img, $oldName);
    if ((strings.lower($oldName) != strings.lower($newName)) and hasFile($img, $newName)) {
        fail("a file named \"" + $newName + "\" is already on this disk");
    }
    $entry.name = $newName;
    return writeEntry($img, $entry);
}

/**
 * Lock a file so `SCRATCH` refuses it.
 *
 * @param {Image}  img  the image
 * @param {string} name the file to lock
 * @return {Image} the image with the entry rewritten
 * @throws {Error} when the file is missing
 * @example
 *   $img = lockFile($img, "hello");
 */
export func lockFile(img as Image, name as string) {
    def entry as Entry init findFile($img, $name);
    $entry.locked = true;
    return writeEntry($img, $entry);
}

/**
 * Unlock a file.
 *
 * @param {Image}  img  the image
 * @param {string} name the file to unlock
 * @return {Image} the image with the entry rewritten
 * @throws {Error} when the file is missing
 * @example
 *   $img = unlockFile($img, "hello");
 */
export func unlockFile(img as Image, name as string) {
    def entry as Entry init findFile($img, $name);
    $entry.locked = false;
    return writeEntry($img, $entry);
}

/**
 * Read one slot of a directory block.
 *
 * @param {bytes} block the directory block
 * @param {int}   index which of the eight slots
 * @param {int}   slot  the slot's position in the whole chain
 * @return {Entry} the entry
 */
func decodeEntry(block as bytes, index as int, slot as int) {
    def at as int init $index * ENTRY_SIZE;
    def raw as int init $block[$at + 2];
    return Entry{
        name: decodeName($block[$at + 5..$at + 5 + MAX_FILENAME]),
        kind: fileTypeFromByte($raw),
        closed: bitSet($raw, 7),
        locked: bitSet($raw, 6),
        track: $block[$at + 3],
        sector: $block[$at + 4],
        blocks: $block[$at + 0x1e] + $block[$at + 0x1f] * 256,
        recordLength: $block[$at + 0x17],
        slot: $slot
    };
}

/**
 * Write an entry back into the slot its `slot` field names.
 *
 * The block's own first two bytes - the chain link - are left alone, because
 * they belong to the block and not to the entry sitting at offset 0.
 *
 * @param {Image} img   the image
 * @param {Entry} entry the entry, with `slot` addressing where it goes
 * @return {Image} the image with the slot rewritten
 * @throws {Error} when the slot is past the end of the directory chain
 */
func writeEntry(img as Image, entry as Entry) {
    def link as Link init entryBlockLink($img, $entry.slot);
    def block as bytes init readSector($img, $link.track, $link.sector);
    def at as int init ($entry.slot % ENTRIES_PER_SECTOR) * ENTRY_SIZE;
    def label as bytes init encodeName($entry.name);
    $block[$at + 2] = fileTypeByte($entry.kind, $entry.closed, $entry.locked);
    $block[$at + 3] = $entry.track;
    $block[$at + 4] = $entry.sector;
    for (def i as int init 0; $i < MAX_FILENAME; $i = $i + 1) {
        $block[$at + 5 + $i] = $label[$i];
    }
    for (def i as int init 0x15; $i <= 0x1d; $i = $i + 1) {
        $block[$at + $i] = 0;
    }
    $block[$at + 0x17] = $entry.recordLength;
    $block[$at + 0x1e] = $entry.blocks & 0xff;
    $block[$at + 0x1f] = ($entry.blocks >> 8) & 0xff;
    return writeSector($img, $link.track, $link.sector, $block);
}

/**
 * Which directory block a slot lives in.
 *
 * @param {Image} img  the image
 * @param {int}   slot the slot index, 0-based across the whole chain
 * @return {Link} the block holding it
 * @throws {Error} when the slot is past the end of the directory chain
 */
func entryBlockLink(img as Image, slot as int) {
    def chain as list of Link init directorySectors($img);
    def which as int init $slot // ENTRIES_PER_SECTOR;
    if ($slot < 0 or $which >= len($chain)) {
        fail("directory slot " + convert.toString($slot) + " is past the end");
    }
    return $chain[$which];
}

/**
 * The first slot no live file occupies, or -1 when the chain is full.
 *
 * A scratched slot counts as free - claiming it is what a real drive does.
 *
 * @param {Image} img the image
 * @return {int} the slot index, or -1
 */
func freeSlotIndex(img as Image) {
    def slot as int init 0;
    for (def link in directorySectors($img)) {
        def block as bytes init readSector($img, $link.track, $link.sector);
        for (def i as int init 0; $i < ENTRIES_PER_SECTOR; $i = $i + 1) {
            if ($block[$i * ENTRY_SIZE + 2] == 0) {
                return $slot;
            }
            $slot = $slot + 1;
        }
    }
    return -1;
}

/**
 * Append one block to the directory chain.
 *
 * The new block is taken from track 18 at the directory interleave of 3, so
 * the chain reads the way a drive wrote it: 18/1, 18/4, 18/7 and on round.
 *
 * @param {Image} img the image
 * @return {Image} the image with a longer directory
 * @throws {Error} when track 18 has no block left
 */
func extendDirectory(img as Image) {
    def chain as list of Link init directorySectors($img);
    def last as Link init $chain[len($chain) - 1];
    def spare as int init freeSectorOnTrack(
        $img,
        DIRECTORY_TRACK,
        ($last.sector + DIRECTORY_INTERLEAVE) % sectorsPerTrack(DIRECTORY_TRACK),
        DIRECTORY_INTERLEAVE);
    if ($spare < 0) {
        fail("the directory is full: all " + convert.toString(MAX_DIRECTORY_ENTRIES) +
            " slots are taken");
    }
    def out as Image init allocateSector($img, DIRECTORY_TRACK, $spare);
    $out = writeSector($out, DIRECTORY_TRACK, $spare, blankDirectorySector());
    def tail as bytes init readSector($out, $last.track, $last.sector);
    $tail[0] = DIRECTORY_TRACK;
    $tail[1] = $spare;
    return writeSector($out, $last.track, $last.sector, $tail);
}

/**
 * The image with at least one free directory slot in it.
 *
 * @param {Image} img the image
 * @return {Image} the image, its directory extended if it had to be
 * @throws {Error} when the directory cannot grow
 */
func ensureFreeSlot(img as Image) {
    if (freeSlotIndex($img) >= 0) {
        return $img;
    }
    return extendDirectory($img);
}
