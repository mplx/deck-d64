# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * d64 - read, write, create and format Commodore 1541 disk images.
 *
 * A D64 file is a byte-for-byte copy of a 5.25" floppy as a 1541 laid it
 * out: 683 blocks of 256 bytes, in four zones of 21, 19, 18 and 17 sectors
 * per track. Inside those blocks lives CBM DOS 2.6 - a Block Availability
 * Map in sector 18/0, a chain of 32-byte directory slots from 18/1, and one
 * linked list of blocks per file. This deck implements all of it:
 *
 *   format   {@link formatDisk} / {@link formatDiskWith} / {@link reformat}
 *   list     {@link listFiles} / {@link findFiles} / {@link directoryText}
 *   read     {@link readFile} / {@link readText} / {@link readProgram}
 *   write    {@link writeFile} / {@link writeText} / {@link writeProgram}
 *   replace  {@link updateFile}
 *   scratch  {@link deleteFile}
 *   blocks   {@link readSector} / {@link writeSector} / {@link blocksFree}
 *
 * Four BAM layouts are supported. `DiskFormat.Cbm` is the stock 35-track one;
 * `SpeedDos`, `DolphinDos` and `PrologicDos` are the three incompatible ways
 * the speeder cartridges recorded the five extra tracks of a 40-track disk.
 * {@link detectFormat} guesses which an image uses and {@link withFormat}
 * overrules the guess.
 *
 * Names and text are PETSCII, which disagrees with ASCII about case:
 * {@link toPetscii} and {@link fromPetscii} transcode both ways, in the
 * lower-case convention `petcat` uses, so `toPetscii("hello")` gives the
 * bytes a C64 shows as `HELLO`.
 *
 * Everything is value-semantic. A function that changes the disk hands back
 * a fresh `Image` and leaves the one you gave it untouched, so the calling
 * shape is always `$img = something($img, ...)`.
 *
 * The implementation is split into topic files, spliced together here with
 * `include` - the module boundary, and every `export`, is this file. The
 * co-located white-box tests live in `d64_test.j`.
 *
 * @module d64
 * @see https://www.c64-wiki.de/wiki/D64
 * @example
 *   import "@mplx/d64/" as d64;
 *
 *   def img as d64.Image init d64.formatDisk("sample disk", "01");
 *   $img = d64.writeText($img, "readme", d64.FileType.Seq, "hello\n");
 *   io.printf("%s", d64.directoryText($img));
 *   d64.save($img, "sample.d64");
 */

use strings;
use convert;
use binary;
use io;
use fs;

include "topics/version.j";
include "topics/core.j";
include "topics/geometry.j";
include "topics/petscii.j";
include "topics/format.j";
include "topics/image.j";
include "topics/bam.j";
include "topics/directory.j";
include "topics/files.j";
