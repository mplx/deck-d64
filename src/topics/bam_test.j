# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the bam topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testHasBamEntry() {
    def img as Image init formatDisk("d", "01");
    testing.assertTrue(hasBamEntry($img, 1));
    testing.assertTrue(hasBamEntry($img, 18));
    testing.assertTrue(hasBamEntry($img, 35));
    testing.assertFalse(hasBamEntry($img, 36));
    testing.assertFalse(hasBamEntry($img, 0));
}

func testHasBamEntryFollowsTheLayout() {
    def speed as Image init fortyTrackDisk(DiskFormat.SpeedDos);
    testing.assertTrue(hasBamEntry($speed, 40));
    testing.assertFalse(hasBamEntry($speed, 41));
}

func testAFreshDiskHasEverythingButTheDirectoryBlocksFree() {
    def img as Image init formatDisk("d", "01");
    testing.assertTrue(isFree($img, 1, 0));
    testing.assertTrue(isFree($img, 35, 16));
    testing.assertFalse(isFree($img, DIRECTORY_TRACK, BAM_SECTOR));
    testing.assertFalse(isFree($img, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR));
    testing.assertTrue(isFree($img, DIRECTORY_TRACK, 2));
}

func testIsAllocatedIsTheInverseOfIsFree() {
    def img as Image init formatDisk("d", "01");
    testing.assertFalse(isAllocated($img, 1, 0));
    testing.assertTrue(isAllocated($img, DIRECTORY_TRACK, BAM_SECTOR));
}

func testATrackWithNoBamEntryIsNeverFree() {
    def img as Image init formatDiskWith(
        FormatOptions{
            tracks: TRACKS_EXTENDED,
            format: DiskFormat.Cbm,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "plain forty",
        "01");
    testing.assertFalse(isFree($img, 36, 0));
    testing.assertTrue(isAllocated($img, 36, 0));
}

func testTrackBlocksFreeMatchesTheZones() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(trackBlocksFree($img, 1), 21);
    testing.assertEqual(trackBlocksFree($img, 17), 21);
    testing.assertEqual(trackBlocksFree($img, 18), 17);
    testing.assertEqual(trackBlocksFree($img, 25), 18);
    testing.assertEqual(trackBlocksFree($img, 35), 17);
}

func testTrackBlocksFreeRejectsTracksOffTheImage() {
    testing.assertThrows("trackBlocksFreePastTheImage", ERROR_KIND);
}

func trackBlocksFreePastTheImage() {
    trackBlocksFree(formatDisk("d", "01"), 36);
}

func testBlocksFreeLeavesTheDirectoryTrackOut() {
    # 683 blocks less the 19 on track 18, which CBM DOS never gives to a file
    testing.assertEqual(blocksFree(formatDisk("d", "01")), 664);
    testing.assertEqual(blocksFree(fortyTrackDisk(DiskFormat.SpeedDos)), 749);
    testing.assertEqual(blocksFree(fortyTrackDisk(DiskFormat.DolphinDos)), 749);
    testing.assertEqual(blocksFree(fortyTrackDisk(DiskFormat.PrologicDos)), 749);
}

func testAllocateSectorMovesOneBitAndOneCount() {
    def img as Image init formatDisk("d", "01");
    def taken as Image init allocateSector($img, 17, 4);
    testing.assertFalse(isFree($taken, 17, 4));
    testing.assertTrue(isFree($taken, 17, 3));
    testing.assertTrue(isFree($taken, 17, 5));
    testing.assertEqual(trackBlocksFree($taken, 17), 20);
    testing.assertEqual(blocksFree($taken), 663);
    # the image it was made from is untouched
    testing.assertTrue(isFree($img, 17, 4));
}

func testFreeSectorIsTheInverse() {
    def img as Image init formatDisk("d", "01");
    def taken as Image init allocateSector($img, 17, 4);
    def back as Image init freeSector($taken, 17, 4);
    testing.assertEqual(toBytes($back), toBytes($img));
}

func testAllocateAndFreeAcrossTheWholeTrack() {
    def img as Image init formatDisk("d", "01");
    for (def s as int init 0; $s < sectorsPerTrack(1); $s = $s + 1) {
        $img = allocateSector($img, 1, $s);
    }
    testing.assertEqual(trackBlocksFree($img, 1), 0);
    for (def s as int init 0; $s < sectorsPerTrack(1); $s = $s + 1) {
        $img = freeSector($img, 1, $s);
    }
    testing.assertEqual(trackBlocksFree($img, 1), 21);
}

func testDoubleAllocateAndDoubleFreeAreRefused() {
    testing.assertThrows("allocateTwice", ERROR_KIND);
    testing.assertThrows("freeWhatIsFree", ERROR_KIND);
    testing.assertThrows("allocateWhereThereIsNoBamEntry", ERROR_KIND);
    testing.assertThrows("freeWhereThereIsNoBamEntry", ERROR_KIND);
}

func allocateTwice() {
    allocateSector(allocateSector(formatDisk("d", "01"), 17, 4), 17, 4);
}

func freeWhatIsFree() {
    freeSector(formatDisk("d", "01"), 17, 4);
}

func allocateWhereThereIsNoBamEntry() {
    allocateSector(fortyTrackDisk(DiskFormat.SpeedDos), 41, 0);
}

func freeWhereThereIsNoBamEntry() {
    freeSector(fortyTrackDisk(DiskFormat.SpeedDos), 41, 0);
}

func testTrackSearchOrderSpiralsOutFromTheDirectory() {
    def order as list of int init trackSearchOrder(formatDisk("d", "01"), 0);
    testing.assertEqual($order[0], 17);
    testing.assertEqual($order[1], 19);
    testing.assertEqual($order[2], 16);
    testing.assertEqual($order[3], 20);
    # every usable track, once, and never the directory track
    testing.assertEqual(len($order), TRACKS_STANDARD - 1);
    testing.assertFalse(lists.contains($order, DIRECTORY_TRACK));
    testing.assertTrue(lists.contains($order, 1));
    testing.assertTrue(lists.contains($order, 35));
}

func testTrackSearchOrderPrefersTheTrackItIsGiven() {
    def order as list of int init trackSearchOrder(formatDisk("d", "01"), 30);
    testing.assertEqual($order[0], 30);
    testing.assertEqual($order[1], 17);
    testing.assertEqual(len($order), TRACKS_STANDARD - 1);
}

func testTrackSearchOrderIgnoresATrackItCannotUse() {
    def order as list of int init trackSearchOrder(formatDisk("d", "01"), DIRECTORY_TRACK);
    testing.assertEqual($order[0], 17);
    def past as list of int init trackSearchOrder(formatDisk("d", "01"), 99);
    testing.assertEqual($past[0], 17);
}

func testTrackSearchOrderCoversTheExtraTracks() {
    def order as list of int init trackSearchOrder(fortyTrackDisk(DiskFormat.SpeedDos), 0);
    testing.assertTrue(lists.contains($order, 40));
    testing.assertFalse(lists.contains($order, 41));
}

func testNextFreeSectorStartsNextToTheDirectory() {
    def found as Link init nextFreeSector(
        formatDisk("d", "01"),
        Link{track: 0, sector: 0},
        FILE_INTERLEAVE);
    testing.assertEqual($found.track, 17);
    testing.assertEqual($found.sector, 0);
}

func testNextFreeSectorSteppsByTheInterleave() {
    def img as Image init allocateSector(formatDisk("d", "01"), 17, 0);
    def found as Link init nextFreeSector($img, Link{track: 17, sector: 0}, FILE_INTERLEAVE);
    testing.assertEqual($found.track, 17);
    testing.assertEqual($found.sector, 10);
}

func testNextFreeSectorWrapsRoundTheTrack() {
    def img as Image init formatDisk("d", "01");
    # interleave 10 on a 21-sector track walks 0, 10, 20, 9, 19, ... and covers it
    def seen as list of int;
    def cursor as Link init Link{track: 17, sector: 0};
    for (def i as int init 0; $i < sectorsPerTrack(17); $i = $i + 1) {
        def found as Link init nextFreeSector($img, $cursor, FILE_INTERLEAVE);
        testing.assertEqual($found.track, 17);
        testing.assertFalse(lists.contains($seen, $found.sector));
        $seen[] = $found.sector;
        $img = allocateSector($img, $found.track, $found.sector);
        $cursor = $found;
    }
    testing.assertEqual(len($seen), 21);
    testing.assertEqual(trackBlocksFree($img, 17), 0);
}

func testNextFreeSectorMovesOnWhenTheTrackIsFull() {
    def img as Image init fillTrack(formatDisk("d", "01"), 17);
    def found as Link init nextFreeSector($img, Link{track: 17, sector: 0}, FILE_INTERLEAVE);
    testing.assertEqual($found.track, 19);
}

func testNextFreeSectorNeverLandsOnTheDirectoryTrack() {
    def img as Image init formatDisk("d", "01");
    for (def t as int init 1; $t <= TRACKS_STANDARD; $t = $t + 1) {
        if ($t != DIRECTORY_TRACK and $t != 25) {
            $img = fillTrack($img, $t);
        }
    }
    def found as Link init nextFreeSector($img, Link{track: 0, sector: 0}, FILE_INTERLEAVE);
    testing.assertEqual($found.track, 25);
}

func testNextFreeSectorRaisesOnAFullDisk() {
    testing.assertThrows("nextFreeSectorOnAFullDisk", ERROR_KIND);
    testing.assertThrows("nextFreeSectorWithNoInterleave", ERROR_KIND);
}

func nextFreeSectorOnAFullDisk() {
    def img as Image init formatDisk("d", "01");
    for (def t as int init 1; $t <= TRACKS_STANDARD; $t = $t + 1) {
        if ($t != DIRECTORY_TRACK) {
            $img = fillTrack($img, $t);
        }
    }
    nextFreeSector($img, Link{track: 0, sector: 0}, FILE_INTERLEAVE);
}

func nextFreeSectorWithNoInterleave() {
    nextFreeSector(formatDisk("d", "01"), Link{track: 0, sector: 0}, 0);
}

func testDiskNameAndId() {
    def img as Image init formatDisk("sample disk", "01");
    testing.assertEqual(diskName($img), "sample disk");
    testing.assertEqual(diskId($img), "01");
    testing.assertEqual(dosType($img), "2a");
    testing.assertEqual(dosVersion($img), DOS_VERSION_BYTE);
}

func testSetDiskNameAndId() {
    def img as Image init formatDisk("sample disk", "01");
    $img = setDiskName($img, "work disk");
    $img = setDiskId($img, "aa");
    testing.assertEqual(diskName($img), "work disk");
    testing.assertEqual(diskId($img), "aa");
    # the DOS type is left where it was
    testing.assertEqual(dosType($img), "2a");
}

func testSetDiskNameShortensCleanly() {
    def img as Image init setDiskName(formatDisk("a very long name", "01"), "ab");
    testing.assertEqual(diskName($img), "ab");
    testing.assertEqual(readSector($img, 18, 0)[0x92], PAD_BYTE);
}

func testTheHeaderMovesUnderPrologicDos() {
    def img as Image init fortyTrackDisk(DiskFormat.PrologicDos);
    testing.assertEqual(diskName($img), "forty track");
    testing.assertEqual(dosType($img), "2a");
    def bam as bytes init readSector($img, 18, 0);
    # the name starts at $a4, and the BAM entry for track 36 sits where it was
    testing.assertEqual($bam[0xa4], 0x46);
    testing.assertEqual($bam[0x90], 17);
    testing.assertEqual($bam[0xb9], 0x32);
    testing.assertEqual($bam[0xba], 0x41);
}

func testSetDiskNameRejectsWhatWillNotFit() {
    testing.assertThrows("setDiskNameTooLong", ERROR_KIND);
    testing.assertThrows("setDiskIdTooLong", ERROR_KIND);
}

func setDiskNameTooLong() {
    setDiskName(formatDisk("d", "01"), "abcdefghijklmnopq");
}

func setDiskIdTooLong() {
    setDiskId(formatDisk("d", "01"), "abc");
}

func fortyTrackDisk(format as DiskFormat) {
    return formatDiskWith(
        FormatOptions{
            tracks: TRACKS_EXTENDED,
            format: $format,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "forty track",
        "40");
}

func fillTrack(img as Image, track as int) {
    def out as Image init $img;
    for (def s as int init 0; $s < sectorsPerTrack($track); $s = $s + 1) {
        if (isFree($out, $track, $s)) {
            $out = allocateSector($out, $track, $s);
        }
    }
    return $out;
}
