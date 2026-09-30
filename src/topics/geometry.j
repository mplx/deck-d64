# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - disk geometry: how tracks, sectors and byte offsets relate.
# Spliced into d64.j via include - not a standalone module.

/** Bytes in one disk block. Every sector on a 1541 is this size. */
export def const SECTOR_SIZE as int init 256;

/** Payload bytes in one block: 256 less the two-byte track/sector link. */
export def const DATA_BYTES_PER_SECTOR as int init 254;

/** The track CBM DOS reserves for the BAM and the directory. */
export def const DIRECTORY_TRACK as int init 18;

/** The sector on {@link DIRECTORY_TRACK} that holds the BAM. */
export def const BAM_SECTOR as int init 0;

/** The sector the directory chain starts on. */
export def const FIRST_DIRECTORY_SECTOR as int init 1;

/** Tracks on a stock 1541 disk. */
export def const TRACKS_STANDARD as int init 35;

/** Tracks on a 40-track disk, as the speeder DOSes format it. */
export def const TRACKS_EXTENDED as int init 40;

/** Tracks on the largest D64 image in circulation. */
export def const TRACKS_MAX as int init 42;

/** Sector interleave CBM DOS uses when it chains file blocks. */
export def const FILE_INTERLEAVE as int init 10;

/** Bytes {@link findBytes} scans per pass; bounds its copying, nothing more. */
def const SEARCH_WINDOW as int init 1024;

/** Sector interleave CBM DOS uses when it chains directory blocks. */
export def const DIRECTORY_INTERLEAVE as int init 3;

/**
 * Sectors on one track.
 *
 * A 1541 writes at a constant bit rate on a constant-speed spindle, so the
 * longer outer tracks hold more sectors than the inner ones - four zones in
 * all. Tracks 36-42 do not exist on a stock drive; they repeat the innermost
 * zone, which is what every 40- and 42-track format does.
 *
 * @param {int} track track number, 1-42
 * @return {int} sectors on that track, 17 to 21
 * @throws {Error} when `track` is outside 1-42
 * @example
 *   sectorsPerTrack(1);    # 21
 *   sectorsPerTrack(18);   # 19
 *   sectorsPerTrack(35);   # 17
 */
export func sectorsPerTrack(track as int) {
    if ($track < 1 or $track > TRACKS_MAX) {
        fail("track " + convert.toString($track) + " is outside 1-42");
    }
    if ($track <= 17) {
        return 21;
    }
    if ($track <= 24) {
        return 19;
    }
    if ($track <= 30) {
        return 18;
    }
    return 17;
}

/**
 * Sectors on a disk of `tracks` tracks, counted from track 1.
 *
 * `0` is allowed and answers `0`, because the offset of a block is the count
 * of every sector on the tracks before it.
 *
 * @param {int} tracks how many tracks, 0-42
 * @return {int} total sectors
 * @throws {Error} when `tracks` is outside 0-42
 * @example
 *   totalSectors(35);   # 683
 *   totalSectors(40);   # 768
 *   totalSectors(42);   # 802
 */
export func totalSectors(tracks as int) {
    if ($tracks < 0 or $tracks > TRACKS_MAX) {
        fail("a disk of " + convert.toString($tracks) + " tracks is outside 0-42");
    }
    # Closed form, not a loop: every block access goes through sectorOffset,
    # which asks for the sectors before its track, so this runs tens of
    # thousands of times for one file and has to be O(1).
    if ($tracks <= 17) {
        return 21 * $tracks;
    }
    if ($tracks <= 24) {
        return 357 + 19 * ($tracks - 17);
    }
    if ($tracks <= 30) {
        return 490 + 18 * ($tracks - 24);
    }
    return 598 + 17 * ($tracks - 30);
}

/**
 * Byte offset of a block inside the image.
 *
 * Blocks are stored back to back in track order, and within a track in sector
 * order, so the offset is the count of every sector before this one times
 * {@link SECTOR_SIZE}.
 *
 * @param {int} track  track number, 1-42
 * @param {int} sector sector number, 0 to `sectorsPerTrack(track) - 1`
 * @return {int} byte offset of the block's first byte
 * @throws {Error} when the track or the sector is out of range
 * @example
 *   sectorOffset(1, 0);     # 0
 *   sectorOffset(18, 0);    # 91392 - the BAM
 */
export func sectorOffset(track as int, sector as int) {
    def limit as int init sectorsPerTrack($track);
    if ($sector < 0 or $sector >= $limit) {
        fail("sector " + convert.toString($sector) + " is outside 0-" +
            convert.toString($limit - 1) + " on track " + convert.toString($track));
    }
    return (totalSectors($track - 1) + $sector) * SECTOR_SIZE;
}

/**
 * Size in bytes of a D64 image with this geometry.
 *
 * An image may carry one error byte per block after the block data - the
 * per-sector result code a mastering tool recorded. Most images do not.
 *
 * @param {int}  tracks    how many tracks, 1-42
 * @param {bool} errorInfo true to include the trailing error-byte table
 * @return {int} image size in bytes
 * @throws {Error} when `tracks` is outside 1-42
 * @example
 *   imageSize(35, false);   # 174848
 *   imageSize(35, true);    # 175531
 */
export func imageSize(tracks as int, errorInfo as bool) {
    def blocks as int init totalSectors($tracks);
    if ($errorInfo) {
        return $blocks * (SECTOR_SIZE + 1);
    }
    return $blocks * SECTOR_SIZE;
}

/**
 * Track count of an image of this size, or 0 when no geometry fits.
 *
 * The six sizes in circulation are 35, 40 and 42 tracks, each with and
 * without the error-byte table.
 *
 * @param {int} size image size in bytes
 * @return {int} 35, 40, 42, or 0 when the size is not a D64
 * @example
 *   tracksForSize(174848);   # 35
 *   tracksForSize(196608);   # 40
 *   tracksForSize(1234);     # 0
 */
export func tracksForSize(size as int) {
    def candidates as list of int init [TRACKS_STANDARD, TRACKS_EXTENDED, TRACKS_MAX];
    for (def t in $candidates) {
        if ($size == imageSize($t, false) or $size == imageSize($t, true)) {
            return $t;
        }
    }
    return 0;
}

/**
 * Whether an image of this size carries the trailing error-byte table.
 *
 * @param {int} size image size in bytes
 * @return {bool} true when the size includes one error byte per block
 * @throws {Error} when the size is not a D64 size at all
 * @example
 *   sizeHasErrorInfo(174848);   # false
 *   sizeHasErrorInfo(175531);   # true
 */
export func sizeHasErrorInfo(size as int) {
    def tracks as int init tracksForSize($size);
    if ($tracks == 0) {
        fail(convert.toString($size) + " bytes is not a D64 image size");
    }
    return $size == imageSize($tracks, true);
}
