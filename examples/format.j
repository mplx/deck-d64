#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * format example - making blank disks, stock and extended.
 *
 * `formatDisk` is `NEW0:NAME,ID` on a 1541: 35 tracks, 664 blocks free.
 * `formatDiskWith` takes the geometry and the BAM layout, which is how you
 * reach the five extra tracks a speeder cartridge formatted.
 *
 *   jennifer run examples/format.j
 */

use io;

import "../src/d64.j" as d64;

def stock as d64.Image init d64.formatDisk("sample disk", "01");
report("cbm", $stock, "");

# the three speeder layouts, each 40 tracks and each parking the five extra
# BAM entries somewhere else in sector 18/0
def speeders as list of string init ["speeddos", "dolphindos", "prologicdos"];
for (def name in $speeders) {
    def disk as d64.Image init extended(d64.formatFromName($name));
    def at as int init d64.bamEntryOffset($disk.format, 40);
    report($name, $disk, io.sprintf("track 40 entry at $%d|base=16", $at));
}

# a 40-track image in the stock layout is legal, but DOS has nowhere to record
# tracks 36-40, so the allocator leaves them alone
report("cbm/40", extended(d64.DiskFormat.Cbm), "tracks 36-40 unreachable");

# an image may carry one error byte per block; most do not
def flagged as d64.Image init d64.formatDiskWith(
    d64.FormatOptions{
        tracks: 35,
        format: d64.DiskFormat.Cbm,
        errorInfo: true,
        dosType: "",
        fill: 0,
        mode: d64.FormatMode.Full
    },
    "error table",
    "01");
report(
    "cbm+errors",
    $flagged,
    io.sprintf("block 18/0 error code %d", d64.sectorError($flagged, 18, 0)));

# quick vs full: both empty the directory, only one clears the blocks
def used as d64.Image init d64.writeText($stock, "gone", d64.FileType.Seq, "bye\n");
def quick as d64.Image init d64.quickFormat($used, "soft");
def full as d64.Image init d64.reformat($used, "hard", "02");

io.printf("\n%s|pad=12|align=left files  block 17/0 byte 2\n", "");
io.printf(
    "%s|pad=12|align=left %d|pad=5|align=right  $%d|base=16\n",
    "before",
    len(d64.listFiles($used)),
    d64.readSector($used, 17, 0)[2]);
io.printf(
    "%s|pad=12|align=left %d|pad=5|align=right  $%d|base=16  (bytes kept)\n",
    "quick",
    len(d64.listFiles($quick)),
    d64.readSector($quick, 17, 0)[2]);
io.printf(
    "%s|pad=12|align=left %d|pad=5|align=right  $%d|base=16  (wiped)\n",
    "full",
    len(d64.listFiles($full)),
    d64.readSector($full, 17, 0)[2]);

# a full format takes a fill byte
def wipe as d64.FormatOptions init d64.defaultFormatOptions();
$wipe.fill = 0xff;
def wiped as d64.Image init d64.reformatWith($used, $wipe, "wiped", "02");
io.printf(
    "%s|pad=12|align=left %d|pad=5|align=right  $%d|base=16  (fill $ff)\n",
    "full ff",
    len(d64.listFiles($wiped)),
    d64.readSector($wiped, 17, 0)[2]);

func extended(format as d64.DiskFormat) {
    def opts as d64.FormatOptions init d64.FormatOptions{
        tracks: 40,
        format: $format,
        errorInfo: false,
        dosType: "",
        fill: 0,
        mode: d64.FormatMode.Full
    };
    return d64.formatDiskWith($opts, "forty track", "40");
}

func report(label as string, disk as d64.Image, note as string) {
    io.printf("%s|pad=12|align=left %d|pad=6|align=right bytes  ", $label, len(d64.toBytes($disk)));
    io.printf(
        "%d|pad=2|align=right tracks  %d|pad=3|align=right free  %s\n",
        $disk.tracks,
        d64.blocksFree($disk),
        $note);
}
