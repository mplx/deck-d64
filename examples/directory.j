#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * directory example - listing a disk the way a 1541 does.
 *
 * `directoryText` renders what `LOAD"$",8` shows; `listFiles` hands back the
 * same thing as typed `Entry` values, and `findFiles` filters them with the
 * drive's own `*` and `?` patterns.
 *
 *   jennifer run examples/directory.j
 */

use io;

import "../src/d64.j" as d64;

def img as d64.Image init d64.formatDisk("sample disk", "01");
$img = d64.writeProgram($img, "hello", 2049, greeting());
$img = d64.writeText($img, "readme", d64.FileType.Seq, "made with jennifer\n");
$img = d64.writeText($img, "notes", d64.FileType.Seq, "second file\n");
$img = d64.writeText($img, "scores", d64.FileType.Usr, "0\n");

# a locked file lists with a trailing "<" and SCRATCH refuses it
$img = d64.lockFile($img, "hello");

io.printf("%s\n", d64.directoryText($img));

io.printf("as entries:\n");
for (def e in d64.listFiles($img)) {
    io.printf(
        "  %s|pad=16|align=left %s  %d|pad=2|align=right block(s)  first at %d/%d\n",
        $e.name,
        d64.fileTypeName($e.kind),
        $e.blocks,
        $e.track,
        $e.sector);
}

io.printf("\nfiles matching \"?e*\":\n");
for (def e in d64.findFiles($img, "?e*")) {
    io.printf("  %s\n", $e.name);
}

io.printf("\nmetadata, chains included:\n");
for (def i in d64.listFileInfo($img)) {
    io.printf(
        "  %s|pad=16|align=left %d|pad=5|align=right bytes  %d|pad=2|align=right block(s)  ",
        $i.entry.name,
        $i.size,
        $i.blocks);
    for (def link in $i.chain) {
        io.printf("%d/%d ", $link.track, $link.sector);
    }
    if ($i.loadAddress >= 0) {
        io.printf(" loads at $%d|base=16", $i.loadAddress);
    }
    io.printf("\n");
}

$img = d64.renameFile($img, "notes", "notes v2");
io.printf("\nrenamed: %t -> %t\n", d64.hasFile($img, "notes"), d64.hasFile($img, "notes v2"));

func greeting() {
    # a two-line BASIC program is beyond the point here - any bytes will do
    def code as bytes;
    for (def i as int init 0; $i < 32; $i = $i + 1) {
        $code[] = $i;
    }
    return $code;
}
