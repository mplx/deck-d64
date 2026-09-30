# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the geometry topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testSectorsPerTrackZones() {
    # the four zones a 1541 records in, at each boundary
    testing.assertEqual(sectorsPerTrack(1), 21);
    testing.assertEqual(sectorsPerTrack(17), 21);
    testing.assertEqual(sectorsPerTrack(18), 19);
    testing.assertEqual(sectorsPerTrack(24), 19);
    testing.assertEqual(sectorsPerTrack(25), 18);
    testing.assertEqual(sectorsPerTrack(30), 18);
    testing.assertEqual(sectorsPerTrack(31), 17);
    testing.assertEqual(sectorsPerTrack(35), 17);
    testing.assertEqual(sectorsPerTrack(40), 17);
    testing.assertEqual(sectorsPerTrack(42), 17);
}

func testSectorsPerTrackRejectsOutOfRange() {
    testing.assertThrows("sectorsPerTrackZero", ERROR_KIND);
    testing.assertThrows("sectorsPerTrackPast42", ERROR_KIND);
}

func sectorsPerTrackZero() {
    sectorsPerTrack(0);
}

func sectorsPerTrackPast42() {
    sectorsPerTrack(43);
}

func testTotalSectorsMatchesTheKnownBlockCounts() {
    testing.assertEqual(totalSectors(0), 0);
    testing.assertEqual(totalSectors(17), 357);
    testing.assertEqual(totalSectors(TRACKS_STANDARD), 683);
    testing.assertEqual(totalSectors(TRACKS_EXTENDED), 768);
    testing.assertEqual(totalSectors(TRACKS_MAX), 802);
}

func testTotalSectorsRejectsOutOfRange() {
    testing.assertThrows("totalSectorsNegative", ERROR_KIND);
    testing.assertThrows("totalSectorsPast42", ERROR_KIND);
}

func totalSectorsNegative() {
    totalSectors(-1);
}

func totalSectorsPast42() {
    totalSectors(43);
}

func testSectorOffsetIsBlockOrder() {
    testing.assertEqual(sectorOffset(1, 0), 0);
    testing.assertEqual(sectorOffset(1, 1), 256);
    testing.assertEqual(sectorOffset(2, 0), 21 * 256);
    # the BAM: 357 blocks on tracks 1-17 come first
    testing.assertEqual(sectorOffset(DIRECTORY_TRACK, BAM_SECTOR), 357 * 256);
    testing.assertEqual(sectorOffset(DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR), 358 * 256);
}

func testSectorOffsetIsContiguous() {
    # every block is exactly SECTOR_SIZE after the one before it, zones and all
    def previous as int init -SECTOR_SIZE;
    for (def t as int init 1; $t <= TRACKS_MAX; $t = $t + 1) {
        for (def s as int init 0; $s < sectorsPerTrack($t); $s = $s + 1) {
            testing.assertEqual(sectorOffset($t, $s), $previous + SECTOR_SIZE);
            $previous = sectorOffset($t, $s);
        }
    }
    testing.assertEqual($previous + SECTOR_SIZE, imageSize(TRACKS_MAX, false));
}

func testSectorOffsetRejectsASectorPastTheTrack() {
    testing.assertThrows("sectorOffsetPastTrack", ERROR_KIND);
    testing.assertThrows("sectorOffsetNegative", ERROR_KIND);
}

func sectorOffsetPastTrack() {
    sectorOffset(18, 19);
}

func sectorOffsetNegative() {
    sectorOffset(1, -1);
}

func testImageSizeMatchesTheSixKnownSizes() {
    testing.assertEqual(imageSize(TRACKS_STANDARD, false), 174848);
    testing.assertEqual(imageSize(TRACKS_STANDARD, true), 175531);
    testing.assertEqual(imageSize(TRACKS_EXTENDED, false), 196608);
    testing.assertEqual(imageSize(TRACKS_EXTENDED, true), 197376);
    testing.assertEqual(imageSize(TRACKS_MAX, false), 205312);
    testing.assertEqual(imageSize(TRACKS_MAX, true), 206114);
}

func testTracksForSize() {
    testing.assertEqual(tracksForSize(174848), 35);
    testing.assertEqual(tracksForSize(175531), 35);
    testing.assertEqual(tracksForSize(196608), 40);
    testing.assertEqual(tracksForSize(205312), 42);
    testing.assertEqual(tracksForSize(206114), 42);
}

func testTracksForSizeRejectsWhatIsNotADisk() {
    testing.assertEqual(tracksForSize(0), 0);
    testing.assertEqual(tracksForSize(1234), 0);
    testing.assertEqual(tracksForSize(174847), 0);
}

func testSizeHasErrorInfo() {
    testing.assertFalse(sizeHasErrorInfo(174848));
    testing.assertTrue(sizeHasErrorInfo(175531));
    testing.assertFalse(sizeHasErrorInfo(196608));
    testing.assertTrue(sizeHasErrorInfo(197376));
}

func testSizeHasErrorInfoRejectsWhatIsNotADisk() {
    testing.assertThrows("sizeHasErrorInfoOnRubbish", ERROR_KIND);
}

func sizeHasErrorInfoOnRubbish() {
    sizeHasErrorInfo(4096);
}

func testTotalSectorsClosedFormMatchesTheSum() {
    # totalSectors is arithmetic, not a loop, because every block access goes
    # through it - so check it against the definition it replaced
    def sum as int init 0;
    for (def t as int init 1; $t <= TRACKS_MAX; $t = $t + 1) {
        $sum = $sum + sectorsPerTrack($t);
        testing.assertEqual(totalSectors($t), $sum);
    }
}
