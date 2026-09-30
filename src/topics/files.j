# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - files: reading, writing and scratching the block chains.
# Spliced into d64.j via include - not a standalone module.

/**
 * A C64 program file, split into the parts BASIC and the loader care about.
 *
 * @field {int}   address the load address the first two bytes of a PRG carry
 * @field {bytes} data    everything after it - the program itself
 */
export def struct Program {
    address as int,
    data as bytes
};

/**
 * The blocks one file occupies, first to last.
 *
 * Each block's first two bytes point at the next; a track byte of 0 ends the
 * chain. The walk is bounded by the size of the disk, so a chain that links
 * back on itself raises rather than running forever.
 *
 * @param {Image} img    the image
 * @param {int}   track  track of the first block, 0 for an empty chain
 * @param {int}   sector sector of the first block
 * @return {list of Link} the blocks, in order
 * @throws {Error} when the chain loops or leaves the disk
 * @example
 *   len(chainOf($img, $entry.track, $entry.sector));   # the file's block count
 */
export func chainOf(img as Image, track as int, sector as int) {
    def chain as list of Link;
    def t as int init $track;
    def s as int init $sector;
    while ($t != 0) {
        if (len($chain) > blockCount($img)) {
            fail("the file chain at " + convert.toString($track) + "/" + convert.toString($sector) +
                " loops");
        }
        $chain[] = Link{track: $t, sector: $s};
        def block as bytes init readSector($img, $t, $s);
        $t = $block[0];
        $s = $block[1];
    }
    return $chain;
}

/**
 * Read a chain of blocks back into one buffer.
 *
 * Every block but the last contributes its full 254 payload bytes. The last
 * one carries its length in the byte where the others carry the next sector:
 * a value of `n` means bytes `$02` through `$n` are the file, so `n - 1`
 * bytes of payload.
 *
 * @param {Image} img    the image
 * @param {int}   track  track of the first block
 * @param {int}   sector sector of the first block
 * @return {bytes} the file's contents
 * @throws {Error} when the chain loops, leaves the disk, or ends badly
 * @example
 *   readChain($img, 17, 0);
 */
export func readChain(img as Image, track as int, sector as int) {
    def out as bytes;
    def links as list of Link init chainOf($img, $track, $sector);
    for (def i as int init 0; $i < len($links); $i = $i + 1) {
        def block as bytes init readSector($img, $links[$i].track, $links[$i].sector);
        def take as int init DATA_BYTES_PER_SECTOR;
        if ($block[0] == 0) {
            if ($block[1] < 1) {
                fail("the last block of the chain claims " + convert.toString($block[1]) +
                    " bytes used, which is not a length");
            }
            $take = $block[1] -1;
        }
        for (def k as int init 0; $k < $take; $k = $k + 1) {
            $out[] = $block[2 + $k];
        }
    }
    return $out;
}

/**
 * Read a file's contents as raw bytes.
 *
 * Nothing is transcoded: a PRG comes back with its two-byte load address in
 * front, a SEQ with whatever bytes were written to it. Use {@link readText}
 * for PETSCII text and {@link readProgram} to split a program's load address
 * off the front.
 *
 * A DEL entry is refused. A listed DEL is a directory slot, not a file: scene
 * disks use them to draw a border, with a first-block pointer left at
 * whatever was there. Following it would return the blocks it happens to name
 * - often the BAM and the directory - as if they were the file.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename, matched exactly
 * @return {bytes} the file's contents
 * @throws {Error} when the file is missing or its chain is broken
 * @example
 *   def raw as bytes init readFile($img, "hello");
 */
export func readFile(img as Image, name as string) {
    def entry as Entry init findFile($img, $name);
    if ($entry.kind == FileType.Del) {
        fail("\"" + $name + "\" is a DEL entry, not a file - its first-block" +
            " pointer means nothing. Use readChain to read blocks directly");
    }
    if ($entry.track == 0) {
        fail("\"" + $name + "\" has no first block - the entry is corrupt");
    }
    return readChain($img, $entry.track, $entry.sector);
}

/**
 * Read a file and transcode it from PETSCII to text.
 *
 * For SEQ and USR text. A PETSCII carriage return becomes a newline, so the
 * result splits on `\n` like any other text.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename
 * @return {string} the file as text
 * @throws {Error} when the file is missing or its chain is broken
 * @example
 *   readText($img, "readme");
 */
export func readText(img as Image, name as string) {
    return fromPetscii(readFile($img, $name));
}

/**
 * Read a PRG and split its load address off the front.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename
 * @return {Program} the load address and the bytes after it
 * @throws {Error} when the file is missing, or is too short to carry an address
 * @example
 *   readProgram($img, "hello").address;   # 2049 - the BASIC start on a C64
 */
export func readProgram(img as Image, name as string) {
    def raw as bytes init readFile($img, $name);
    if (len($raw) < 2) {
        fail("\"" + $name + "\" is " + convert.toString(len($raw)) +
            " bytes - too short to carry a load address");
    }
    return Program{address: $raw[0] + $raw[1] * 256, data: $raw[2..]};
}

/**
 * Write a new file.
 *
 * The blocks are taken at the standard interleave of 10 and chained; a
 * directory slot is claimed, extending the directory by one block if every
 * slot is taken. The file must not already exist - {@link updateFile}
 * replaces one that does.
 *
 * REL files are not written: their side-sector index is a second structure
 * this deck does not build. Reading one back with {@link readFile} works,
 * because the data chain is an ordinary chain.
 *
 * @param {Image}    img  the image
 * @param {string}   name the filename, 1 to 16 characters
 * @param {FileType} kind SEQ, PRG or USR
 * @param {bytes}    data the file's contents
 * @return {Image} the image with the file on it
 * @throws {Error} when the name is taken or unfit, the kind is REL or DEL, or
 *                 the disk or the directory is full
 * @example
 *   $img = writeFile($img, "hello", FileType.Prg, $bytes);
 */
export func writeFile(img as Image, name as string, kind as FileType, data as bytes) {
    checkWritable($img, $name, $kind);
    def blocks as int init blocksForBytes(len($data));
    def out as Image init ensureFreeSlot($img);
    if (blocksFree($out) < $blocks) {
        fail("the disk holds " + convert.toString(blocksFree($out)) + " free blocks; \"" + $name +
            "\" needs " + convert.toString($blocks));
    }
    def chain as list of Link;
    def cursor as Link init Link{track: 0, sector: 0};
    for (def i as int init 0; $i < $blocks; $i = $i + 1) {
        $cursor = nextFreeSector($out, $cursor, FILE_INTERLEAVE);
        $out = allocateSector($out, $cursor.track, $cursor.sector);
        $chain[] = $cursor;
    }
    $out = storeChain($out, $chain, $data);
    return addEntry($out, $name, $kind, $chain[0], $blocks);
}

/**
 * Write text to a new file, transcoded to PETSCII.
 *
 * @param {Image}    img  the image
 * @param {string}   name the filename, 1 to 16 characters
 * @param {FileType} kind SEQ, PRG or USR - SEQ for plain text
 * @param {string}   text the text to store
 * @return {Image} the image with the file on it
 * @throws {Error} when the name is taken or unfit, or the disk is full
 * @example
 *   $img = writeText($img, "readme", FileType.Seq, "hello\nworld\n");
 */
export func writeText(img as Image, name as string, kind as FileType, text as string) {
    return writeFile($img, $name, $kind, toPetscii($text));
}

/**
 * Write a PRG, putting its load address in front of the data.
 *
 * @param {Image}  img     the image
 * @param {string} name    the filename, 1 to 16 characters
 * @param {int}    address the load address, 0 to 65535
 * @param {bytes}  data    the program bytes
 * @return {Image} the image with the program on it
 * @throws {Error} when the address is out of range, or the write fails
 * @example
 *   $img = writeProgram($img, "hello", 2049, $basic);
 */
export func writeProgram(img as Image, name as string, address as int, data as bytes) {
    if ($address < 0 or $address > 0xffff) {
        fail("a load address is 0 to 65535, not " + convert.toString($address));
    }
    def raw as bytes;
    $raw[] = $address & 0xff;
    $raw[] = ($address >> 8) & 0xff;
    for (def i as int init 0; $i < len($data); $i = $i + 1) {
        $raw[] = $data[$i];
    }
    return writeFile($img, $name, FileType.Prg, $raw);
}

/**
 * Replace a file, or write it when it is not there yet.
 *
 * The old copy is scratched first and its blocks go back to the BAM, so the
 * new copy may well land on them. That means the update is not a transaction:
 * if it fails half-way the image you passed in is still intact - value
 * semantics see to that - but the one you would have got back is not.
 *
 * @param {Image}    img  the image
 * @param {string}   name the filename
 * @param {FileType} kind SEQ, PRG or USR
 * @param {bytes}    data the new contents
 * @return {Image} the image with the file replaced
 * @throws {Error} when the file is locked, or the new copy will not fit
 * @example
 *   $img = updateFile($img, "hello", FileType.Prg, $newBytes);
 */
export func updateFile(img as Image, name as string, kind as FileType, data as bytes) {
    def out as Image init $img;
    if (hasFile($out, $name)) {
        $out = deleteFile($out, $name);
    }
    return writeFile($out, $name, $kind, $data);
}

/**
 * Scratch a file.
 *
 * Its blocks go back to the BAM and the directory slot's type byte is zeroed
 * - which is all a real `SCRATCH` does. The name and the block pointer stay
 * in the slot until something claims it, which is why an undelete tool can
 * sometimes get a file back.
 *
 * @param {Image}  img  the image
 * @param {string} name the file to scratch
 * @return {Image} the image without the file
 * @throws {Error} when the file is missing or locked
 * @example
 *   $img = deleteFile($img, "hello");
 */
export func deleteFile(img as Image, name as string) {
    def entry as Entry init findFile($img, $name);
    if ($entry.locked) {
        fail("\"" + $name + "\" is locked - unlock it before scratching it");
    }
    if ($entry.kind == FileType.Del) {
        # A DEL entry owns no blocks, whatever its first-block pointer says -
        # scene disks use them to draw a border and leave that pointer at
        # whatever was there, often the BAM. Freeing what it points at would
        # hand the filesystem its own directory back as free space.
        return scratchEntry($img, $entry.slot);
    }
    def out as Image init $img;
    for (def link in chainOf($img, $entry.track, $entry.sector)) {
        $out = freeSector($out, $link.track, $link.sector);
    }
    return scratchEntry($out, $entry.slot);
}

/**
 * Refuse a write that cannot work before any block is touched.
 *
 * @param {Image}    img  the image
 * @param {string}   name the filename
 * @param {FileType} kind the file type asked for
 * @throws {Error} when the name is taken or unfit, or the kind cannot be written
 */
func checkWritable(img as Image, name as string, kind as FileType) {
    encodeName($name);
    if (hasFile($img, $name)) {
        fail("a file named \"" + $name + "\" is already on this disk");
    }
    if ($kind == FileType.Rel) {
        fail("REL files need a side-sector index this deck does not build");
    }
    if ($kind == FileType.Del) {
        fail("DEL is the type of a scratched slot, not a file you can write");
    }
    return;
}

/**
 * Write a payload across a chain of blocks that is already allocated.
 *
 * Writes straight into one copy of the image rather than going through
 * {@link writeSector} per block: a disk-filling file is 664 blocks, and a
 * copy of the whole image each way for every one of them is the difference
 * between a moment and several seconds.
 *
 * @param {Image}        img   the image
 * @param {list of Link} chain the blocks, in order
 * @param {bytes}        data  the payload
 * @return {Image} the image with the blocks written
 */
func storeChain(img as Image, chain as list of Link, data as bytes) {
    def raw as bytes init $img.data;
    for (def i as int init 0; $i < len($chain); $i = $i + 1) {
        def at as int init checkedOffset($img, $chain[$i].track, $chain[$i].sector);
        def start as int init $i * DATA_BYTES_PER_SECTOR;
        def take as int init len($data) - $start;
        if ($take > DATA_BYTES_PER_SECTOR) {
            $take = DATA_BYTES_PER_SECTOR;
        }
        if ($take < 0) {
            $take = 0;
        }
        if ($i + 1 < len($chain)) {
            $raw[$at] = $chain[$i + 1].track;
            $raw[$at + 1] = $chain[$i + 1].sector;
        } else {
            $raw[$at] = 0;
            $raw[$at + 1] = $take + 1;
        }
        for (def k as int init 0; $k < $take; $k = $k + 1) {
            $raw[$at + 2 + $k] = $data[$start + $k];
        }
        for (def k as int init $take; $k < DATA_BYTES_PER_SECTOR; $k = $k + 1) {
            $raw[$at + 2 + $k] = 0;
        }
    }
    def out as Image init $img;
    $out.data = $raw;
    return $out;
}

/**
 * Claim the first free directory slot for a new file.
 *
 * @param {Image}    img    the image, already known to have a free slot
 * @param {string}   name   the filename
 * @param {FileType} kind   the file type
 * @param {Link}     first  the file's first block
 * @param {int}      blocks the file's length in blocks
 * @return {Image} the image with the entry written
 * @throws {Error} when no slot is free after all
 */
func addEntry(img as Image, name as string, kind as FileType, first as Link, blocks as int) {
    def slot as int init freeSlotIndex($img);
    if ($slot < 0) {
        fail("the directory is full: all " + convert.toString(MAX_DIRECTORY_ENTRIES) +
            " slots are taken");
    }
    def entry as Entry init Entry{
        name: $name,
        kind: $kind,
        closed: true,
        locked: false,
        track: $first.track,
        sector: $first.sector,
        blocks: $blocks,
        recordLength: 0,
        slot: $slot
    };
    return writeEntry($img, $entry);
}

/**
 * Zero the type byte of one directory slot, the way `SCRATCH` does.
 *
 * @param {Image} img  the image
 * @param {int}   slot the slot to scratch
 * @return {Image} the image with the slot marked deleted
 * @throws {Error} when the slot is past the end of the directory chain
 */
func scratchEntry(img as Image, slot as int) {
    def link as Link init entryBlockLink($img, $slot);
    def block as bytes init readSector($img, $link.track, $link.sector);
    $block[($slot % ENTRIES_PER_SECTOR) * ENTRY_SIZE + 2] = 0;
    return writeSector($img, $link.track, $link.sector, $block);
}

/**
 * Everything the disk records about one file, plus the blocks it occupies.
 *
 * The directory entry says where a file starts and how long it claims to be;
 * only walking the chain says where it actually is and how long it actually
 * is. This carries both, so a disagreement is visible rather than assumed
 * away.
 *
 * @field {Entry}        entry       the directory entry, verbatim
 * @field {list of Link} chain       every block, first to last
 * @field {int}          blocks      blocks in the chain
 * @field {int}          size        payload bytes over the whole chain
 * @field {int}          lastUsed    payload bytes in the last block
 * @field {int}          loadAddress the PRG load address, -1 when there is none
 * @field {bool}         blocksMatch whether the entry's block count is right
 */
export def struct FileInfo {
    entry as Entry,
    chain as list of Link,
    blocks as int,
    size as int,
    lastUsed as int,
    loadAddress as int,
    blocksMatch as bool
};

/**
 * Extract one file's metadata, chain included.
 *
 * Reads the chain and the first and last blocks; it does not read the file.
 * A DEL entry reports an empty chain, because the pointer in a DEL slot names
 * no file - see {@link deleteFile}.
 *
 * @param {Image}  img  the image
 * @param {string} name the filename, matched exactly
 * @return {FileInfo} the metadata
 * @throws {Error} when the file is missing or its chain is broken
 * @example
 *   def info as FileInfo init fileInfo($img, "demo");
 *   $info.size;           # payload bytes
 *   $info.blocks;         # blocks actually chained
 *   $info.loadAddress;    # 2049 for a BASIC program
 *   len($info.chain);     # same as $info.blocks
 */
export func fileInfo(img as Image, name as string) {
    return entryInfo($img, findFile($img, $name));
}

/**
 * Extract the metadata of every file on the disk, in directory order.
 *
 * @param {Image} img the image
 * @return {list of FileInfo} one entry per live file
 * @example
 *   for (def i in listFileInfo($img)) {
 *       io.printf("%s %d bytes\n", $i.entry.name, $i.size);
 *   }
 */
export func listFileInfo(img as Image) {
    def out as list of FileInfo;
    for (def e in listFiles($img)) {
        $out[] = entryInfo($img, $e);
    }
    return $out;
}

/**
 * Walk one entry's chain and measure what it points at.
 *
 * @param {Image} img   the image
 * @param {Entry} entry the directory entry
 * @return {FileInfo} the metadata
 * @throws {Error} when the chain loops or leaves the disk
 */
func entryInfo(img as Image, entry as Entry) {
    def chain as list of Link;
    if ($entry.kind != FileType.Del) {
        $chain = chainOf($img, $entry.track, $entry.sector);
    }
    def used as int init 0;
    def size as int init 0;
    if (len($chain) > 0) {
        def tail as Link init $chain[len($chain) - 1];
        def last as bytes init readSector($img, $tail.track, $tail.sector);
        if ($last[0] == 0 and $last[1] >= 1) {
            $used = $last[1] -1;
        }
        $size = (len($chain) - 1) * DATA_BYTES_PER_SECTOR + $used;
    }
    return FileInfo{
        entry: $entry,
        chain: $chain,
        blocks: len($chain),
        size: $size,
        lastUsed: $used,
        loadAddress: loadAddressOf($img, $entry, $chain, $size),
        blocksMatch: $entry.blocks == len($chain)
    };
}

/**
 * The load address in the first two payload bytes of a PRG.
 *
 * @param {Image}        img   the image
 * @param {Entry}        entry the directory entry
 * @param {list of Link} chain the file's blocks
 * @param {int}          size  the payload size
 * @return {int} the address, or -1 when the file is not a PRG or is too short
 */
func loadAddressOf(img as Image, entry as Entry, chain as list of Link, size as int) {
    if ($entry.kind != FileType.Prg or len($chain) == 0 or $size < 2) {
        return -1;
    }
    def head as bytes init readSector($img, $chain[0].track, $chain[0].sector);
    return $head[2] + $head[3] * 256;
}

/**
 * Overwrite part of a file in place, without moving or resizing it.
 *
 * The blocks the file already holds are patched where they sit, so the chain,
 * the directory entry and the BAM are all untouched - the difference from
 * {@link updateFile}, which scratches the old copy and allocates a new one.
 * That makes this the way to patch a program on a disk: nothing else on the
 * disk moves.
 *
 * A patch cannot change the length. Writing past the end raises rather than
 * growing the file.
 *
 * @param {Image}  img    the image
 * @param {string} name   the filename, matched exactly
 * @param {int}    offset where in the file to start, 0 is the first byte
 * @param {bytes}  data   the bytes to write, at least one
 * @return {Image} the image with the file patched
 * @throws {Error} when the file is missing, or the patch is empty or overruns
 * @example
 *   $img = patchFile($img, "demo", 2, toPetscii("hi"));
 *   readFile($img, "demo")[2];   # $48
 */
export func patchFile(img as Image, name as string, offset as int, data as bytes) {
    if (len($data) == 0) {
        fail("a patch needs at least one byte");
    }
    def info as FileInfo init fileInfo($img, $name);
    if ($offset < 0 or $offset + len($data) > $info.size) {
        fail("a patch of " + convert.toString(len($data)) + " bytes at " +
            convert.toString($offset) + " does not fit \"" + $name + "\", which holds " +
            convert.toString($info.size) + " - a patch cannot change the length");
    }
    def raw as bytes init $img.data;
    def current as int init -1;
    def base as int init 0;
    for (def i as int init 0; $i < len($data); $i = $i + 1) {
        def pos as int init $offset + $i;
        def which as int init $pos // DATA_BYTES_PER_SECTOR;
        if ($which != $current) {
            $current = $which;
            $base = sectorOffset($info.chain[$which].track, $info.chain[$which].sector) + 2;
        }
        $raw[$base + ($pos % DATA_BYTES_PER_SECTOR)] = $data[$i];
    }
    def out as Image init $img;
    $out.data = $raw;
    return $out;
}
