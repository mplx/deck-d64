#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * files example - the whole file life cycle on one disk.
 *
 * Write, read back, replace, scratch - and save the image to a real .d64 and
 * open it again, which is the only part of the deck that touches the
 * filesystem.
 *
 *   jennifer run examples/files.j
 */

use io;
use fs;
use path;
use os;

import "../src/d64.j" as d64;

def img as d64.Image init d64.formatDisk("work disk", "wd");
io.printf("blank disk: %d blocks free\n", d64.blocksFree($img));

# text goes in as PETSCII and comes back out as text
$img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\nfrom jennifer\n");
io.printf("readme reads back as: %s", d64.readText($img, "readme"));

# a program carries its load address in the first two bytes
$img = d64.writeProgram($img, "demo", 0x0801, payload(700));
def prg as d64.Program init d64.readProgram($img, "demo");
io.printf(
    "demo loads at $%d|base=16 and is %d bytes over %d block(s)\n",
    $prg.address,
    len($prg.data),
    d64.findFile($img, "demo").blocks);

# the chain the allocator built, at the standard interleave of 10
def entry as d64.Entry init d64.findFile($img, "demo");
io.printf("its blocks:");
for (def link in d64.chainOf($img, $entry.track, $entry.sector)) {
    io.printf(" %d/%d", $link.track, $link.sector);
}
io.printf("\n%d blocks free\n\n", d64.blocksFree($img));

# replacing a file scratches the old copy first, so the blocks come back
$img = d64.updateFile($img, "demo", d64.FileType.Prg, payload(10));
io.printf("after replacing demo with a smaller one: %d blocks free\n", d64.blocksFree($img));

$img = d64.deleteFile($img, "readme");
io.printf(
    "after scratching readme: %d blocks free, %d file(s) left\n\n",
    d64.blocksFree($img),
    len(d64.listFiles($img)));

# out to a real .d64 and back in
def target as string init path.join(os.tempDir(), "jennifer-d64-example.d64");
d64.save($img, $target);
defer fs.remove($target);

def again as d64.Image init d64.open($target);
io.printf("wrote %s (%d bytes)\n", $target, len(d64.toBytes($again)));
io.printf(
    "reopened: \"%s\" id %s, %d file(s), %d blocks free\n",
    d64.diskName($again),
    d64.diskId($again),
    len(d64.listFiles($again)),
    d64.blocksFree($again));

func payload(n as int) {
    def out as bytes;
    for (def i as int init 0; $i < $n; $i = $i + 1) {
        $out[] = $i % 256;
    }
    return $out;
}
