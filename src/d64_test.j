# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

/**
 * White-box unit tests for the d64 module.
 *
 * Runs as the co-located test overlay: `jennifer test src/d64_test.j`.
 * The tests are split into topic files under `topics/`, spliced together
 * here with `include` - one test file per implementation topic file, in the
 * same order `d64.j` splices the topics themselves.
 *
 * The whole deck is pure computation over a byte buffer, so every path is
 * covered here: the four zones of the geometry, the PETSCII transcoder in
 * both directions, all four BAM layouts, the allocator's interleave and its
 * spiral out from the directory track, the directory chain as it grows past
 * its first block, and the block chains of files from empty to disk-filling.
 * The two functions that touch the filesystem - `open` and `save` - are
 * thin `fs` wrappers over `fromBytes` and `toBytes`, which are covered; the
 * examples exercise them end to end.
 */

use testing;
use strings;
use lists;
use convert;

include "topics/core_test.j";
include "topics/geometry_test.j";
include "topics/petscii_test.j";
include "topics/format_test.j";
include "topics/image_test.j";
include "topics/bam_test.j";
include "topics/directory_test.j";
include "topics/files_test.j";
