#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * sectors example - the layer under the filesystem.
 *
 * `readSector` and `writeSector` address the disk the way the drive's
 * block commands do, and the BAM calls say what is free. Between them you
 * can look at - or build - structures CBM DOS knows nothing about, which is
 * what every copy-protection scheme on the platform did.
 *
 *   jennifer run examples/sectors.j
 */

use io;
use encoding;

import "../src/d64.j" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");
$img = d64.writeText($img, "hello", d64.FileType.Prg, "x");

# the four recording zones, and where each track starts in the file
io.printf("track  sectors  offset    free\n");
def probes as list of int init [1, 17, 18, 24, 25, 30, 31, 35];
for (def t in $probes) {
    io.printf(
        "%d|pad=5|align=right  %d|pad=7|align=right  %d|pad=8|align=right  %d|pad=4|align=right\n",
        $t,
        d64.sectorsPerTrack($t),
        d64.sectorOffset($t, 0),
        d64.trackBlocksFree($img, $t));
}

# sector 18/0 is the BAM, and its header carries the name, the ID and the
# DOS type - 16 bytes of name from $90, then $a0 $a0, the ID, $a0, "2A"
def bam as bytes init d64.readSector($img, 18, 0);
io.printf(
    "\nbam 18/0 first bytes : %s  (link to 18/1, DOS version $%d|base=16)\n",
    encoding.toText($bam[0..4], "hex"),
    $bam[2]);
io.printf("bam 18/0 header      : %s\n", encoding.toText($bam[0x90..0xab], "hex"));
io.printf(
    "bam entry for track 1: %s  (%d free, bits 0-20 set)\n",
    encoding.toText($bam[0x04..0x08], "hex"),
    $bam[0x04]);

# the first directory slot, 32 bytes of it
def dir as bytes init d64.readSector($img, 18, 1);
io.printf("\ndirectory slot 0     : %s\n", encoding.toText($dir[0..32], "hex"));
io.printf(
    "  type byte $%d|base=16  first block %d/%d  %d block(s)\n",
    $dir[2],
    $dir[3],
    $dir[4],
    $dir[0x1e] + $dir[0x1f] * 256);

# the file's one data block: link 00/02 means "last block, one byte used"
def block as bytes init d64.readSector($img, 17, 0);
io.printf("\nfile block 17/0      : %s ...\n", encoding.toText($block[0..8], "hex"));

# a block range: the BAM and the first directory block, read as one run
def run as bytes init d64.readBlocks($img, d64.Link{track: 18, sector: 0}, 2);
io.printf(
    "\nblocks 18/0-18/1     : %d bytes, numbers %d..%d\n",
    len($run),
    d64.blockNumber(18, 0),
    d64.blockNumber(18, 1));

# claim a block outside the filesystem and write to it directly
$img = d64.allocateSector($img, 1, 0);
def custom as bytes init d64.readSector($img, 1, 0);
$custom[0] = 0xc7;
$custom[1] = 0x00;
$img = d64.writeSector($img, 1, 0, $custom);
io.printf(
    "\nafter claiming 1/0   : free=%t, %d blocks free, reads back $%d|base=16\n",
    d64.isFree($img, 1, 0),
    d64.blocksFree($img),
    d64.readSector($img, 1, 0)[0]);
