#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * Every result the documentation claims, asserted against the code.
 *
 * The guides annotate their snippets with the value each call returns
 * (`blocksFree($img);   # 664`). This runs those calls and checks the numbers,
 * so a deliberate behaviour change fails here until the docs are updated with
 * it. Run by tools/check-docs.sh; exits non-zero on the first disagreement it
 * reports.
 *
 * Adding a claim to a guide means adding it here. The static half of the check
 * - signatures, fields, links - is in tools/check-docs.sh.
 */

use io;
use convert;
use encoding;

import "../src/d64.j" as d64;

def failures as int init 0;

/**
 * Compare one documented value against the real one.
 *
 * @param {string} what the doc path, a space, then what is being claimed
 * @param {string} got  what the code answered
 * @param {string} want what the docs say
 */
func check(what as string, got as string, want as string) {
    # every claim is reported, so check-docs.sh can hold the guides to the set
    # of values asserted here - a number edited in a guide alone is then a
    # claim nothing backs, and fails
    io.printf("claim %s => %s\n", $what, $want);
    if ($got != $want) {
        io.printf("  MISMATCH %s: code says %s, docs say %s\n", $what, $got, $want);
        $failures = $failures + 1;
    }
}

/**
 * Compare a documented integer.
 *
 * @param {string} what the doc path, a space, then what is being claimed
 * @param {int}    got  what the code answered
 * @param {int}    want what the docs say
 */
func checkInt(what as string, got as int, want as int) {
    check($what, convert.toString($got), convert.toString($want));
}

/**
 * Compare a documented boolean.
 *
 * @param {string} what the doc path, a space, then what is being claimed
 * @param {bool}   got  what the code answered
 * @param {bool}   want what the docs say
 */
func checkBool(what as string, got as bool, want as bool) {
    check($what, convert.toString($got), convert.toString($want));
}

/**
 * A payload of `n` counting bytes.
 *
 * @param {int} n how many bytes
 * @return {bytes} the payload
 */
func counting(n as int) {
    def out as bytes;
    for (def i as int init 0; $i < $n; $i = $i + 1) {
        $out[] = $i % 256;
    }
    return $out;
}

/**
 * Format options for a 40-track disk in one of the speeder layouts.
 *
 * @param {d64.DiskFormat} format the layout
 * @return {d64.FormatOptions} the options
 */
func fortyTrack(format as d64.DiskFormat) {
    return d64.FormatOptions{
        tracks: 40,
        format: $format,
        errorInfo: false,
        dosType: "",
        fill: 0,
        mode: d64.FormatMode.Full
    };
}

# ------------------------------------------ docs/guide/format.md, docs/index.md

def img as d64.Image init d64.formatDisk("sample disk", "01");
checkInt("docs/guide/format.md len(toBytes)", len(d64.toBytes($img)), 174848);
checkInt("docs/guide/format.md blocksFree", d64.blocksFree($img), 664);
check("docs/guide/format.md diskName", d64.diskName($img), "sample disk");
check("docs/guide/format.md diskId", d64.diskId($img), "01");
check("docs/guide/format.md dosType", d64.dosType($img), "2a");

def forty as d64.Image init d64.formatDiskWith(
    fortyTrack(d64.DiskFormat.SpeedDos),
    "forty track",
    "40");
checkInt("docs/guide/format.md 40-track len", len(d64.toBytes($forty)), 196608);
checkInt("docs/guide/format.md 40-track blocksFree", d64.blocksFree($forty), 749);
checkInt("docs/reference/cheatsheet.md 40-track blocksFree", d64.blocksFree($forty), 749);

checkInt(
    "docs/guide/format.md bamEntryOffset speeddos 36",
    d64.bamEntryOffset(d64.DiskFormat.SpeedDos, 36),
    192);
checkInt(
    "docs/guide/format.md bamEntryOffset dolphindos 36",
    d64.bamEntryOffset(d64.DiskFormat.DolphinDos, 36),
    172);
checkInt(
    "docs/guide/format.md bamEntryOffset cbm 36",
    d64.bamEntryOffset(d64.DiskFormat.Cbm, 36),
    -1);

def plain as d64.Image init d64.formatDiskWith(fortyTrack(d64.DiskFormat.Cbm), "plain forty", "01");
checkInt("docs/guide/format.md cbm/40 blocksFree", d64.blocksFree($plain), 664);
checkBool("docs/guide/format.md cbm/40 hasBamEntry 36", d64.hasBamEntry($plain, 36), false);
checkBool("docs/guide/format.md cbm/40 isFree 36/0", d64.isFree($plain, 36, 0), false);

def errorOptions as d64.FormatOptions init d64.defaultFormatOptions();
$errorOptions.errorInfo = true;
def flagged as d64.Image init d64.formatDiskWith($errorOptions, "protected", "01");
checkInt("docs/guide/format.md sectorError 18/0", d64.sectorError($flagged, 18, 0), 1);

def wipe as d64.FormatOptions init d64.defaultFormatOptions();
$wipe.fill = 0xff;
def wiped as d64.Image init d64.reformatWith($img, $wipe, "wiped", "02");
checkInt("docs/guide/format.md fill byte readSector", d64.readSector($wiped, 17, 0)[0], 255);

def before as d64.Image init d64.formatDisk("work", "01");
def after as d64.Image init d64.writeText($before, "readme", d64.FileType.Seq, "hi\n");
checkInt("docs/index.md listFiles before", len(d64.listFiles($before)), 0);
checkInt("docs/index.md listFiles after", len(d64.listFiles($after)), 1);

# -------------------------------------------------------- docs/guide/petscii.md

check(
    "docs/guide/petscii.md toPetscii hello",
    encoding.toText(d64.toPetscii("hello"), "hex"),
    "48454c4c4f");
check(
    "docs/index.md toPetscii hello",
    encoding.toText(d64.toPetscii("hello"), "hex"),
    "48454c4c4f");
check(
    "docs/guide/petscii.md toPetscii Hello",
    encoding.toText(d64.toPetscii("Hello"), "hex"),
    "c8454c4c4f");
check(
    "docs/guide/petscii.md toPetscii braces",
    encoding.toText(d64.toPetscii('a{b}'), "hex"),
    "413f423f");
check(
    "docs/guide/petscii.md encodeName",
    encoding.toText(d64.encodeName("hello"), "hex"),
    "48454c4c4fa0a0a0a0a0a0a0a0a0a0a0");
check("docs/guide/petscii.md decodeName", d64.decodeName(d64.encodeName("hello")), "hello");
# the two-charset examples: the same bytes, two readings
def border as bytes init d64.toPetsciiIn("╭──╮", d64.Charset.Unshifted);
check(
    "docs/guide/petscii.md unshifted round trip",
    d64.fromPetsciiIn($border, d64.Charset.Unshifted),
    "╭──╮");
check(
    "docs/guide/petscii.md shifted reading of the same bytes",
    d64.fromPetsciiIn($border, d64.Charset.Shifted),
    "U──I");
checkBool("docs/guide/petscii.md matchName star", d64.matchName("*", "anything"), true);
checkBool("docs/guide/petscii.md matchName prefix", d64.matchName("he*", "hello"), true);
checkBool("docs/guide/petscii.md matchName question", d64.matchName("h?llo", "hello"), true);
checkBool("docs/guide/petscii.md matchName shorter", d64.matchName("hello", "hell"), false);

# -------------------------------------------------------- docs/guide/sectors.md

checkInt("docs/guide/sectors.md blocksFree", d64.blocksFree($img), 664);
checkInt("docs/guide/sectors.md sectorsPerTrack 1", d64.sectorsPerTrack(1), 21);
checkInt("docs/guide/sectors.md sectorsPerTrack 18", d64.sectorsPerTrack(18), 19);
checkInt("docs/guide/sectors.md totalSectors 35", d64.totalSectors(35), 683);
checkInt("docs/guide/sectors.md sectorOffset 1/0", d64.sectorOffset(1, 0), 0);
checkInt("docs/guide/sectors.md sectorOffset 18/0", d64.sectorOffset(18, 0), 91392);
checkInt("docs/guide/sectors.md bam[2]", d64.readSector($img, 18, 0)[2], 0x41);
checkInt(
    "docs/guide/sectors.md len(readBlocks 2)",
    len(d64.readBlocks($img, d64.Link{track: 18, sector: 0}, 2)),
    512);
checkInt("docs/guide/sectors.md blockNumber 1/0", d64.blockNumber(1, 0), 0);
checkInt("docs/guide/sectors.md blockNumber 18/0", d64.blockNumber(18, 0), 357);
checkInt("docs/guide/sectors.md blockLink(357).track", d64.blockLink(357).track, 18);
checkInt("docs/guide/sectors.md blockLink(357).sector", d64.blockLink(357).sector, 0);
checkInt("docs/guide/sectors.md trackBlocksFree 1", d64.trackBlocksFree($img, 1), 21);
checkInt("docs/guide/sectors.md trackBlocksFree 18", d64.trackBlocksFree($img, 18), 17);
checkBool("docs/guide/sectors.md isFree 17/0", d64.isFree($img, 17, 0), true);
checkBool("docs/guide/sectors.md isAllocated 18/0", d64.isAllocated($img, 18, 0), true);

def spiral as list of int init d64.trackSearchOrder($img, 0);
def wantSpiral as list of int init [17, 19, 16, 20, 15, 21];
for (def i as int init 0; $i < len($wantSpiral); $i = $i + 1) {
    checkInt(
        "docs/guide/sectors.md trackSearchOrder " + convert.toString($i),
        $spiral[$i],
        $wantSpiral[$i]);
}
def preferred as list of int init d64.trackSearchOrder($img, 30);
def wantPreferred as list of int init [30, 17, 19, 16];
for (def i as int init 0; $i < len($wantPreferred); $i = $i + 1) {
    checkInt(
        "docs/guide/sectors.md trackSearchOrder(30) " + convert.toString($i),
        $preferred[$i],
        $wantPreferred[$i]);
}

# --------------------------------------- docs/guide/files.md, docs/guide/directory.md

def withProgram as d64.Image init d64.writeProgram($img, "demo", 0x0801, counting(20));
checkInt(
    "docs/guide/files.md readProgram address",
    d64.readProgram($withProgram, "demo").address,
    2049);
checkInt(
    "docs/guide/files.md fileInfo loadAddress",
    d64.fileInfo($withProgram, "demo").loadAddress,
    2049);
checkInt(
    "docs/guide/files.md fileInfo loadAddress of a seq",
    d64.fileInfo($after, "readme").loadAddress,
    -1);

checkInt("docs/guide/directory.md directorySectors fresh", len(d64.directorySectors($img)), 1);
def nine as d64.Image init $img;
for (def i as int init 0; $i < 9; $i = $i + 1) {
    $nine = d64.writeText($nine, "f" + convert.toString($i), d64.FileType.Seq, "x");
}
checkInt(
    "docs/guide/directory.md directorySectors after nine files",
    len(d64.directorySectors($nine)),
    2);

# ---------------------------------------------------------------- the listings
#
# Printed between markers; check-docs.sh checks every line appears verbatim in
# the guide that shows it. Catches drift in directoryText's own formatting.

def listing as d64.Image init d64.formatDisk("sample disk", "01");
$listing = d64.writeProgram($listing, "hello", 2049, counting(32));
$listing = d64.writeText($listing, "readme", d64.FileType.Seq, "made with jennifer\n");
$listing = d64.writeText($listing, "notes", d64.FileType.Seq, "second file\n");
$listing = d64.writeText($listing, "scores", d64.FileType.Usr, "0\n");
$listing = d64.lockFile($listing, "hello");
io.printf("<<<listing docs/guide/directory.md\n%s>>>\n", d64.directoryText($listing));

def readme as d64.Image init d64.formatDisk("sample disk", "01");
$readme = d64.writeText($readme, "readme", d64.FileType.Seq, "hello from jennifer\n");
$readme = d64.writeProgram($readme, "demo", 0x0801, counting(600));
io.printf("<<<listing README.md\n%s>>>\n", d64.directoryText($readme));

if ($failures > 0) {
    io.printf("%d documented value(s) disagree with the code\n", $failures);
    exit 1;
}
io.printf("every documented value matches the code\n");
