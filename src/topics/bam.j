# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - the Block Availability Map: what is free, what is taken, and the
# disk header that shares sector 18/0 with it.
# Spliced into d64.j via include - not a standalone module.

/**
 * Whether a track is covered by this disk's BAM.
 *
 * Tracks 1-35 always are. Tracks 36-40 are only under the three speeder
 * layouts, and tracks 41-42 never are - see {@link bamEntryOffset}.
 *
 * @param {Image} img   the image
 * @param {int}   track track number
 * @return {bool} true when the track has four BAM bytes of its own
 * @example
 *   hasBamEntry(formatDisk("d", "01"), 18);   # true
 */
export func hasBamEntry(img as Image, track as int) {
    if ($track < 1 or $track > $img.tracks) {
        return false;
    }
    return bamEntryOffset($img.format, $track) >= 0;
}

/**
 * Whether a block is free.
 *
 * A block on a track the BAM does not cover is never free - nothing can be
 * allocated there, because there would be no way to record it.
 *
 * @param {Image} img    the image
 * @param {int}   track  track number
 * @param {int}   sector sector number within the track
 * @return {bool} true when the block is available
 * @throws {Error} when the address is outside the image
 * @example
 *   isFree(formatDisk("d", "01"), 18, 0);   # false - that is the BAM itself
 */
export func isFree(img as Image, track as int, sector as int) {
    checkedOffset($img, $track, $sector);
    def at as int init bamEntryOffset($img.format, $track);
    if ($at < 0) {
        return false;
    }
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return bitSet($bam[$at + 1 + ($sector // 8)], $sector % 8);
}

/**
 * Whether a block is taken - the inverse of {@link isFree}.
 *
 * @param {Image} img    the image
 * @param {int}   track  track number
 * @param {int}   sector sector number within the track
 * @return {bool} true when the block is in use or unavailable
 * @throws {Error} when the address is outside the image
 * @example
 *   isAllocated(formatDisk("d", "01"), 18, 1);   # true
 */
export func isAllocated(img as Image, track as int, sector as int) {
    return not isFree($img, $track, $sector);
}

/**
 * Free blocks on one track, as the BAM's own count byte reports it.
 *
 * @param {Image} img   the image
 * @param {int}   track track number
 * @return {int} free blocks, 0 when the track has no BAM entry
 * @throws {Error} when the track is outside the image
 * @example
 *   trackBlocksFree(formatDisk("d", "01"), 1);    # 21
 *   trackBlocksFree(formatDisk("d", "01"), 18);   # 17 of 19
 */
export func trackBlocksFree(img as Image, track as int) {
    if ($track < 1 or $track > $img.tracks) {
        fail("track " + convert.toString($track) + " is outside 1-" +
            convert.toString($img.tracks) + " on this image");
    }
    def at as int init bamEntryOffset($img.format, $track);
    if ($at < 0) {
        return 0;
    }
    return readSector($img, DIRECTORY_TRACK, BAM_SECTOR)[$at];
}

/**
 * Free blocks a file could use, which is what a 1541 prints.
 *
 * Track 18 is left out of the sum: CBM DOS keeps it for the BAM and the
 * directory and never puts file data there, so its free blocks are not
 * blocks you can store anything in. A freshly formatted 35-track disk
 * answers 664.
 *
 * @param {Image} img the image
 * @return {int} allocatable free blocks
 * @example
 *   blocksFree(formatDisk("sample", "01"));   # 664
 */
export func blocksFree(img as Image) {
    # one BAM read, not one per track: writeFile asks for this before every
    # file, and trackBlocksFree would re-slice the same sector 35 times
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    def total as int init 0;
    for (def t as int init 1; $t <= $img.tracks; $t = $t + 1) {
        def at as int init bamEntryOffset($img.format, $t);
        if ($t != DIRECTORY_TRACK and $at >= 0) {
            $total = $total + $bam[$at];
        }
    }
    return $total;
}

/**
 * Mark a block taken.
 *
 * Allocating a block that is already taken is an error, not a silent no-op -
 * it means two chains would share it, which is how a disk loses a file.
 *
 * @param {Image} img    the image
 * @param {int}   track  track number
 * @param {int}   sector sector number within the track
 * @return {Image} the image with the block allocated
 * @throws {Error} when the block is already taken or has no BAM entry
 * @example
 *   $img = allocateSector($img, 17, 0);
 */
export func allocateSector(img as Image, track as int, sector as int) {
    if (not isFree($img, $track, $sector)) {
        fail("block " + convert.toString($track) + "/" + convert.toString($sector) +
            " is already allocated");
    }
    return setBamBit($img, $track, $sector, false);
}

/**
 * Mark a block free.
 *
 * Freeing a block that is already free is an error for the same reason
 * allocating a taken one is: it means the count byte and the bitmap have
 * drifted apart.
 *
 * @param {Image} img    the image
 * @param {int}   track  track number
 * @param {int}   sector sector number within the track
 * @return {Image} the image with the block freed
 * @throws {Error} when the block is already free or has no BAM entry
 * @example
 *   $img = freeSector($img, 17, 0);
 */
export func freeSector(img as Image, track as int, sector as int) {
    if (bamEntryOffset($img.format, $track) < 0) {
        fail("track " + convert.toString($track) + " has no BAM entry under " +
            formatName($img.format));
    }
    if (isFree($img, $track, $sector)) {
        fail("block " + convert.toString($track) + "/" + convert.toString($sector) +
            " is already free");
    }
    return setBamBit($img, $track, $sector, true);
}

/**
 * Find the next free block to chain onto, the way CBM DOS does.
 *
 * The search stays on `near`'s track while it has room, stepping `interleave`
 * sectors on at a time - the gap that lets the drive read the next block
 * without waiting a whole revolution. When the track fills, the search
 * spirals outward from the directory track: 17, 19, 16, 20, and so on, so
 * a file lands as close to the directory as it can.
 *
 * @param {Image} img        the image
 * @param {Link}  near       where to start looking; `Link{track: 0, sector: 0}`
 *                           means "anywhere"
 * @param {int}   interleave sectors to skip between blocks, 1 or more
 * @return {Link} the block found
 * @throws {Error} when the disk is full
 * @example
 *   def first as Link init nextFreeSector($img, Link{track: 0, sector: 0}, 10);
 */
export func nextFreeSector(img as Image, near as Link, interleave as int) {
    if ($interleave < 1) {
        fail("an interleave is 1 or more, not " + convert.toString($interleave));
    }
    for (def track in trackSearchOrder($img, $near.track)) {
        def start as int init 0;
        if ($track == $near.track) {
            $start = ($near.sector + $interleave) % sectorsPerTrack($track);
        }
        def found as int init freeSectorOnTrack($img, $track, $start, $interleave);
        if ($found >= 0) {
            return Link{track: $track, sector: $found};
        }
    }
    fail("the disk is full: no free block left");
    return Link{track: 0, sector: 0};
}

/**
 * The order the allocator walks tracks in.
 *
 * `preferred` comes first when it can still hold data; the rest spiral out
 * from the directory track, nearest first. Track 18 never appears - it is
 * the directory's - and neither does a track with no BAM entry.
 *
 * @param {Image} img       the image
 * @param {int}   preferred the track to try first, 0 for none
 * @return {list of int} the tracks to try, in order
 * @example
 *   trackSearchOrder(formatDisk("d", "01"), 0)[0];   # 17
 */
export func trackSearchOrder(img as Image, preferred as int) {
    def order as list of int;
    def first as int init 0;
    if ($preferred >= 1 and $preferred <= $img.tracks and $preferred != DIRECTORY_TRACK and
        hasBamEntry($img, $preferred)) {
        $first = $preferred;
        $order[] = $preferred;
    }
    # The spiral visits 18-step and 18+step, distinct for every step >= 1, so
    # no track can repeat and no dedupe scan is needed. This runs once per
    # allocated block; a `lists.contains` over the growing list made it
    # quadratic in the track count.
    for (def step as int init 1; $step < TRACKS_MAX; $step = $step + 1) {
        def below as int init DIRECTORY_TRACK - $step;
        if ($below != $first and hasBamEntry($img, $below)) {
            $order[] = $below;
        }
        def above as int init DIRECTORY_TRACK + $step;
        if ($above != $first and hasBamEntry($img, $above)) {
            $order[] = $above;
        }
    }
    return $order;
}

/**
 * The first free sector on one track, hunting by interleave then linearly.
 *
 * The interleave walk visits `start`, `start + interleave` and so on, which
 * only covers the whole track when the two are coprime; a linear sweep picks
 * up whatever it missed, so a track with any free block always yields one.
 *
 * @param {Image} img        the image
 * @param {int}   track      the track to search
 * @param {int}   start      the sector to try first
 * @param {int}   interleave sectors to skip between tries
 * @return {int} the sector found, or -1 when the track is full
 */
func freeSectorOnTrack(img as Image, track as int, start as int, interleave as int) {
    def at as int init bamEntryOffset($img.format, $track);
    if ($at < 0) {
        return -1;
    }
    # the track's bitmap, read once - this runs for every block of every file,
    # so re-reading the BAM sector per candidate sector would dominate a write
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    def count as int init sectorsPerTrack($track);
    for (def i as int init 0; $i < $count; $i = $i + 1) {
        def s as int init ($start + $i * $interleave) % $count;
        if (bitSet($bam[$at + 1 + ($s // 8)], $s % 8)) {
            return $s;
        }
    }
    for (def s as int init 0; $s < $count; $s = $s + 1) {
        if (bitSet($bam[$at + 1 + ($s // 8)], $s % 8)) {
            return $s;
        }
    }
    return -1;
}

/**
 * Set or clear one bit of the BAM and fix the track's count byte with it.
 *
 * @param {Image} img    the image
 * @param {int}   track  track number
 * @param {int}   sector sector number within the track
 * @param {bool}  free   true to mark free, false to mark taken
 * @return {Image} the image with the BAM updated
 */
func setBamBit(img as Image, track as int, sector as int, free as bool) {
    # straight into one copy of the image: every allocated block comes through
    # here, and a read-modify-write of the whole BAM sector for each would cost
    # two copies of the image per block
    def base as int init sectorOffset(DIRECTORY_TRACK, BAM_SECTOR) +
        bamEntryOffset($img.format, $track);
    def byteAt as int init $base + 1 + ($sector // 8);
    def raw as bytes init $img.data;
    if ($free) {
        $raw[$byteAt] = setBit($raw[$byteAt], $sector % 8);
        $raw[$base] = $raw[$base] + 1;
    } else {
        $raw[$byteAt] = clearBit($raw[$byteAt], $sector % 8);
        $raw[$base] = $raw[$base] -1;
    }
    def out as Image init $img;
    $out.data = $raw;
    return $out;
}

/**
 * The disk name, as the header of a directory listing shows it.
 *
 * @param {Image} img the image
 * @return {string} the name, pad bytes trimmed
 * @example
 *   diskName(formatDisk("sample disk", "01"));   # "sample disk"
 */
export func diskName(img as Image) {
    return diskNameIn($img, Charset.Shifted);
}

/**
 * The disk name, read in a chosen character set.
 *
 * `Charset.Unshifted` is what shows a name drawn out of border graphics
 * rather than the run of capitals a shifted reading makes of it.
 *
 * @param {Image}   img     the image
 * @param {Charset} charset which character set to read it in
 * @return {string} the name, pad bytes trimmed
 * @example
 *   diskNameIn($img, Charset.Unshifted);
 */
export func diskNameIn(img as Image, charset as Charset) {
    def at as int init headerOffsetFor($img.format);
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return decodeNameIn($bam[$at..$at + MAX_FILENAME], $charset);
}

/**
 * Rename the disk.
 *
 * @param {Image}  img  the image
 * @param {string} name the new name, 1 to 16 characters
 * @return {Image} the image with the header rewritten
 * @throws {Error} when the name will not fit
 * @example
 *   $img = setDiskName($img, "work disk");
 */
export func setDiskName(img as Image, name as string) {
    def at as int init headerOffsetFor($img.format);
    def label as bytes init encodeName($name);
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    for (def i as int init 0; $i < MAX_FILENAME; $i = $i + 1) {
        $bam[$at + $i] = $label[$i];
    }
    return writeSector($img, DIRECTORY_TRACK, BAM_SECTOR, $bam);
}

/**
 * The two-character disk ID.
 *
 * @param {Image} img the image
 * @return {string} the ID
 * @example
 *   diskId(formatDisk("sample", "01"));   # "01"
 */
export func diskId(img as Image) {
    def at as int init headerOffsetFor($img.format) + 0x12;
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return decodeName($bam[$at..$at + 2]);
}

/**
 * Change the disk ID.
 *
 * On real hardware the ID is what the drive compares to decide whether the
 * disk was swapped, so changing it on a disk that is already written is a
 * thing to do deliberately.
 *
 * @param {Image}  img the image
 * @param {string} id  the new ID, one or two characters
 * @return {Image} the image with the header rewritten
 * @throws {Error} when the ID will not fit
 * @example
 *   $img = setDiskId($img, "aa");
 */
export func setDiskId(img as Image, id as string) {
    def at as int init headerOffsetFor($img.format) + 0x12;
    def code as bytes init encodeDiskId($id);
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    $bam[$at] = $code[0];
    $bam[$at + 1] = $code[1];
    return writeSector($img, DIRECTORY_TRACK, BAM_SECTOR, $bam);
}

/**
 * The two-character DOS type, `"2A"` on everything a 1541 wrote.
 *
 * @param {Image} img the image
 * @return {string} the DOS type
 * @example
 *   dosType(formatDisk("sample", "01"));   # "2a"
 */
export func dosType(img as Image) {
    def at as int init headerOffsetFor($img.format) + 0x15;
    def bam as bytes init readSector($img, DIRECTORY_TRACK, BAM_SECTOR);
    return decodeName($bam[$at..$at + 2]);
}

/**
 * The DOS version byte at offset `$02` of the BAM.
 *
 * `$41` is what CBM DOS writes. A disk with anything else there is refused by
 * a real drive unless the drive's own version byte is patched to match -
 * which is exactly what some copy-protection schemes did.
 *
 * @param {Image} img the image
 * @return {int} the version byte
 * @example
 *   dosVersion(formatDisk("sample", "01"));   # 65
 */
export func dosVersion(img as Image) {
    return readSector($img, DIRECTORY_TRACK, BAM_SECTOR)[2];
}
