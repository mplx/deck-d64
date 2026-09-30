# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the image topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testFromBytesReadsTheGeometryOffTheLength() {
    def img as Image init fromBytes(zeroBytes(174848));
    testing.assertEqual($img.tracks, TRACKS_STANDARD);
    testing.assertFalse($img.errorInfo);

    def withErrors as Image init fromBytes(zeroBytes(175531));
    testing.assertEqual($withErrors.tracks, TRACKS_STANDARD);
    testing.assertTrue($withErrors.errorInfo);

    def big as Image init fromBytes(zeroBytes(205312));
    testing.assertEqual($big.tracks, TRACKS_MAX);
}

func testFromBytesRejectsWhatIsNotADisk() {
    testing.assertThrows("fromBytesOnRubbish", ERROR_KIND);
    testing.assertThrows("fromBytesOnEmpty", ERROR_KIND);
}

func fromBytesOnRubbish() {
    fromBytes(zeroBytes(4096));
}

func fromBytesOnEmpty() {
    fromBytes(zeroBytes(0));
}

func testToBytesRoundTrips() {
    def img as Image init formatDisk("round trip", "rt");
    def again as Image init fromBytes(toBytes($img));
    testing.assertEqual(toBytes($again), toBytes($img));
    testing.assertEqual($again.tracks, $img.tracks);
    testing.assertEqual($again.errorInfo, $img.errorInfo);
    testing.assertEqual(diskName($again), "round trip");
}

func testBlockCount() {
    testing.assertEqual(blockCount(formatDisk("d", "01")), 683);
    testing.assertEqual(blockCount(fromBytes(zeroBytes(196608))), 768);
    testing.assertEqual(blockCount(fromBytes(zeroBytes(205312))), 802);
}

func testReadSectorIsAlwaysAWholeBlock() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(len(readSector($img, 1, 0)), SECTOR_SIZE);
    testing.assertEqual(len(readSector($img, 35, 16)), SECTOR_SIZE);
}

func testWriteSectorThenReadSector() {
    def img as Image init formatDisk("d", "01");
    def block as bytes init zeroBytes(SECTOR_SIZE);
    $block[0] = 0x2a;
    $block[255] = 0xc3;
    $img = writeSector($img, 17, 5, $block);
    testing.assertEqual(readSector($img, 17, 5), $block);
    # no neighbouring block moved
    testing.assertEqual(readSector($img, 17, 4)[0], 0x00);
    testing.assertEqual(readSector($img, 17, 6)[0], 0x00);
}

func testWriteSectorLeavesTheOriginalAlone() {
    def img as Image init formatDisk("d", "01");
    def changed as Image init writeSector($img, 1, 0, filledBlock(0x55));
    testing.assertEqual(readSector($changed, 1, 0)[0], 0x55);
    testing.assertEqual(readSector($img, 1, 0)[0], 0x00);
}

func testWriteSectorRejectsABlockOfTheWrongSize() {
    testing.assertThrows("writeSectorShortBlock", ERROR_KIND);
}

func writeSectorShortBlock() {
    writeSector(formatDisk("d", "01"), 1, 0, zeroBytes(255));
}

func testSectorAddressesAreCheckedAgainstTheImage() {
    testing.assertThrows("readSectorPastTheLastTrack", ERROR_KIND);
    testing.assertThrows("readSectorOnTrackZero", ERROR_KIND);
    testing.assertThrows("readSectorPastTheTrack", ERROR_KIND);
}

func readSectorPastTheLastTrack() {
    # legal on a 40-track image, not on this one
    readSector(formatDisk("d", "01"), 36, 0);
}

func readSectorOnTrackZero() {
    readSector(formatDisk("d", "01"), 0, 0);
}

func readSectorPastTheTrack() {
    readSector(formatDisk("d", "01"), 18, 19);
}

func testAnImageWithNoErrorTableReportsEveryBlockGood() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(sectorError($img, 1, 0), ERROR_OK);
    testing.assertEqual(sectorError($img, 18, 0), ERROR_OK);
}

func testSetSectorErrorNeedsAnErrorTable() {
    testing.assertThrows("setSectorErrorWithNoTable", ERROR_KIND);
}

func setSectorErrorWithNoTable() {
    setSectorError(formatDisk("d", "01"), 1, 0, 0x0b);
}

func testSetSectorErrorRecordsOneBlock() {
    def img as Image init errorTableDisk();
    $img = setSectorError($img, 17, 3, 0x0b);
    testing.assertEqual(sectorError($img, 17, 3), 0x0b);
    # its neighbours are still good, and so is the block data
    testing.assertEqual(sectorError($img, 17, 2), ERROR_OK);
    testing.assertEqual(sectorError($img, 17, 4), ERROR_OK);
    testing.assertEqual(len(toBytes($img)), 175531);
}

func testSetSectorErrorRejectsWhatIsNotAByte() {
    testing.assertThrows("setSectorErrorTooBig", ERROR_KIND);
}

func setSectorErrorTooBig() {
    setSectorError(errorTableDisk(), 1, 0, 256);
}

func testClearErrorTableWipesEveryCode() {
    def img as Image init setSectorError(errorTableDisk(), 17, 3, 0x0b);
    $img = clearErrorTable($img);
    testing.assertEqual(sectorError($img, 17, 3), ERROR_OK);
}

func testClearErrorTableIsANoOpWithoutOne() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(toBytes(clearErrorTable($img)), toBytes($img));
}

func testErrorTableIsAddressedPerBlock() {
    # every block has its own byte, and the last one is the last byte of the file
    def img as Image init setSectorError(errorTableDisk(), TRACKS_STANDARD, 16, 0x05);
    def raw as bytes init toBytes($img);
    testing.assertEqual($raw[len($raw) - 1], 0x05);
    testing.assertEqual($raw[len($raw) - 2], ERROR_OK);
}

func testWithFormatOverridesTheGuess() {
    def img as Image init formatDiskWith(
        FormatOptions{
            tracks: TRACKS_EXTENDED,
            format: DiskFormat.SpeedDos,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "speed",
        "sd");
    testing.assertEqual($img.format, DiskFormat.SpeedDos);

    def asDolphin as Image init withFormat($img, DiskFormat.DolphinDos);
    testing.assertEqual($asDolphin.format, DiskFormat.DolphinDos);
    # nothing on the disk moved, only how the BAM is read
    testing.assertEqual(toBytes($asDolphin), toBytes($img));
    testing.assertEqual(trackBlocksFree($asDolphin, 40), 0);
}

func filledBlock(value as int) {
    def block as bytes init zeroBytes(SECTOR_SIZE);
    for (def i as int init 0; $i < SECTOR_SIZE; $i = $i + 1) {
        $block[$i] = $value;
    }
    return $block;
}

func errorTableDisk() {
    return formatDiskWith(
        FormatOptions{
            tracks: TRACKS_STANDARD,
            format: DiskFormat.Cbm,
            errorInfo: true,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "with errors",
        "01");
}

# -------------------------------------------------------------- block ranges

func testBlockNumberIsTheImageOrder() {
    testing.assertEqual(blockNumber(1, 0), 0);
    testing.assertEqual(blockNumber(1, 20), 20);
    testing.assertEqual(blockNumber(2, 0), 21);
    testing.assertEqual(blockNumber(DIRECTORY_TRACK, BAM_SECTOR), 357);
    testing.assertEqual(blockNumber(TRACKS_MAX, 16), totalSectors(TRACKS_MAX) - 1);
}

func testBlockLinkIsTheInverse() {
    for (def n as int init 0; $n < totalSectors(TRACKS_MAX); $n = $n + 1) {
        def link as Link init blockLink($n);
        testing.assertEqual(blockNumber($link.track, $link.sector), $n);
    }
}

func testBlockLinkRejectsWhatIsOffTheDisk() {
    testing.assertThrows("blockLinkNegative", ERROR_KIND);
    testing.assertThrows("blockLinkPastTheEnd", ERROR_KIND);
}

func blockLinkNegative() {
    blockLink(-1);
}

func blockLinkPastTheEnd() {
    blockLink(totalSectors(TRACKS_MAX));
}

func testReadBlocksSpansTracks() {
    def img as Image init formatDisk("d", "01");
    # the last two blocks of track 1 and the first of track 2
    def run as bytes init readBlocks($img, Link{track: 1, sector: 19}, 3);
    testing.assertEqual(len($run), 3 * SECTOR_SIZE);
    testing.assertEqual($run[0..SECTOR_SIZE], readSector($img, 1, 19));
    testing.assertEqual($run[SECTOR_SIZE..2 * SECTOR_SIZE], readSector($img, 1, 20));
    testing.assertEqual($run[2 * SECTOR_SIZE..3 * SECTOR_SIZE], readSector($img, 2, 0));
}

func testReadBlocksIgnoresTheBam() {
    # allocated, free and system blocks all read alike
    def img as Image init writeText(formatDisk("d", "01"), "hello", FileType.Seq, "x");
    def run as bytes init readBlocks($img, Link{track: DIRECTORY_TRACK, sector: 0}, 2);
    testing.assertEqual($run[0], DIRECTORY_TRACK);
    testing.assertEqual($run[2], DOS_VERSION_BYTE);
    testing.assertEqual($run[SECTOR_SIZE + 1], 0xff);
    testing.assertEqual(len(readBlocks($img, Link{track: 17, sector: 0}, 1)), SECTOR_SIZE);
}

func testWriteBlocksRoundTrips() {
    def img as Image init formatDisk("d", "01");
    def run as bytes init zeroBytes(2 * SECTOR_SIZE);
    $run[0] = 0xc7;
    $run[SECTOR_SIZE] = 0x2a;
    $run[2 * SECTOR_SIZE - 1] = 0x5f;

    def out as Image init writeBlocks($img, Link{track: 1, sector: 20}, $run);
    testing.assertEqual(readBlocks($out, Link{track: 1, sector: 20}, 2), $run);
    testing.assertEqual(readSector($out, 1, 20)[0], 0xc7);
    testing.assertEqual(readSector($out, 2, 0)[0], 0x2a);
    # neighbours untouched, and the BAM knows nothing about it
    testing.assertEqual(readSector($out, 1, 19)[0], 0x00);
    testing.assertEqual(readSector($out, 2, 1)[0], 0x00);
    testing.assertTrue(isFree($out, 1, 20));
    testing.assertTrue(isFree($out, 2, 0));
}

func testWriteBlocksOverAFileIsAllowed() {
    # no BAM bookkeeping: the range calls will overwrite a file's blocks
    def img as Image init writeText(formatDisk("d", "01"), "hello", FileType.Seq, "x");
    def out as Image init writeBlocks($img, Link{track: 17, sector: 0}, zeroBytes(SECTOR_SIZE));
    testing.assertFalse(isFree($out, 17, 0));
    testing.assertEqual(readSector($out, 17, 0)[1], 0x00);
}

func testBlockRangesAreCheckedAgainstTheImage() {
    testing.assertThrows("readBlocksPastTheEnd", ERROR_KIND);
    testing.assertThrows("readBlocksWithNoCount", ERROR_KIND);
    testing.assertThrows("readBlocksOffTheImage", ERROR_KIND);
    testing.assertThrows("writeBlocksWithAPartialBlock", ERROR_KIND);
    testing.assertThrows("writeBlocksWithNothing", ERROR_KIND);
    testing.assertThrows("writeBlocksPastTheEnd", ERROR_KIND);
}

func readBlocksPastTheEnd() {
    readBlocks(formatDisk("d", "01"), Link{track: 35, sector: 15}, 3);
}

func readBlocksWithNoCount() {
    readBlocks(formatDisk("d", "01"), Link{track: 1, sector: 0}, 0);
}

func readBlocksOffTheImage() {
    readBlocks(formatDisk("d", "01"), Link{track: 36, sector: 0}, 1);
}

func writeBlocksWithAPartialBlock() {
    writeBlocks(formatDisk("d", "01"), Link{track: 1, sector: 0}, zeroBytes(255));
}

func writeBlocksWithNothing() {
    writeBlocks(formatDisk("d", "01"), Link{track: 1, sector: 0}, zeroBytes(0));
}

func writeBlocksPastTheEnd() {
    writeBlocks(formatDisk("d", "01"), Link{track: 35, sector: 16}, zeroBytes(2 * SECTOR_SIZE));
}

func testAWholeDiskRoundTripsThroughABlockRange() {
    def img as Image init writeText(formatDisk("d", "01"), "hello", FileType.Seq, "x");
    def all as bytes init readBlocks($img, Link{track: 1, sector: 0}, blockCount($img));
    testing.assertEqual($all, toBytes($img));
    testing.assertEqual(
        toBytes(writeBlocks(formatDisk("other", "02"), Link{track: 1, sector: 0}, $all)),
        toBytes($img));
}

# -------------------------------------------------------------- byte editing

func testPatchSectorLeavesTheRestOfTheBlock() {
    def img as Image init formatDisk("d", "01");
    def before as bytes init readSector($img, 17, 0);
    def patch as bytes;
    $patch[] = 0xc7;
    $patch[] = 0x2a;

    def out as Image init patchSector($img, 17, 0, 10, $patch);
    def after as bytes init readSector($out, 17, 0);
    testing.assertEqual($after[10], 0xc7);
    testing.assertEqual($after[11], 0x2a);
    testing.assertEqual($after[0..10], $before[0..10]);
    testing.assertEqual($after[12..SECTOR_SIZE], $before[12..SECTOR_SIZE]);
}

func testPatchSectorReachesTheLastByte() {
    def patch as bytes;
    $patch[] = 0x5f;
    def img as Image init patchSector(formatDisk("d", "01"), 1, 0, 255, $patch);
    testing.assertEqual(readSector($img, 1, 0)[255], 0x5f);
}

func testPatchSectorRejectsAnOverrun() {
    testing.assertThrows("patchSectorPastTheBlock", ERROR_KIND);
    testing.assertThrows("patchSectorWithNothing", ERROR_KIND);
    testing.assertThrows("patchSectorNegative", ERROR_KIND);
}

func patchSectorPastTheBlock() {
    def patch as bytes;
    $patch[] = 1;
    $patch[] = 2;
    patchSector(formatDisk("d", "01"), 1, 0, 255, $patch);
}

func patchSectorWithNothing() {
    patchSector(formatDisk("d", "01"), 1, 0, 0, zeroBytes(0));
}

func patchSectorNegative() {
    def patch as bytes;
    $patch[] = 1;
    patchSector(formatDisk("d", "01"), 1, 0, -1, $patch);
}

func testReadAtAndWriteAtCrossBlocks() {
    def img as Image init formatDisk("d", "01");
    def at as int init sectorOffset(1, 0) + 254;
    def data as bytes;
    for (def i as int init 0; $i < 4; $i = $i + 1) {
        $data[] = 0xa0 + $i;
    }
    def out as Image init writeAt($img, $at, $data);
    testing.assertEqual(readAt($out, $at, 4), $data);
    # the run wrote straight through the block boundary
    testing.assertEqual(readSector($out, 1, 0)[254], 0xa0);
    testing.assertEqual(readSector($out, 1, 0)[255], 0xa1);
    testing.assertEqual(readSector($out, 1, 1)[0], 0xa2);
    testing.assertEqual(readSector($out, 1, 1)[1], 0xa3);
}

func testReadAtAgreesWithReadSector() {
    def img as Image init writeText(formatDisk("d", "01"), "hello", FileType.Seq, "x");
    testing.assertEqual(readAt($img, sectorOffset(18, 0), SECTOR_SIZE), readSector($img, 18, 0));
}

func testByteRangesAreChecked() {
    testing.assertThrows("readAtPastTheEnd", ERROR_KIND);
    testing.assertThrows("readAtNegative", ERROR_KIND);
    testing.assertThrows("readAtNothing", ERROR_KIND);
    testing.assertThrows("writeAtPastTheEnd", ERROR_KIND);
}

func readAtPastTheEnd() {
    readAt(formatDisk("d", "01"), 174848 - 2, 4);
}

func readAtNegative() {
    readAt(formatDisk("d", "01"), -1, 2);
}

func readAtNothing() {
    readAt(formatDisk("d", "01"), 0, 0);
}

func writeAtPastTheEnd() {
    def data as bytes;
    $data[] = 1;
    $data[] = 2;
    writeAt(formatDisk("d", "01"), 174848 - 1, $data);
}

func testTheErrorTableIsOutsideTheByteView() {
    # readAt addresses blocks only; the trailing table has its own accessors
    testing.assertThrows("readAtIntoTheErrorTable", ERROR_KIND);
}

func readAtIntoTheErrorTable() {
    def img as Image init formatDiskWith(
        FormatOptions{
            tracks: 35,
            format: DiskFormat.Cbm,
            errorInfo: true,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "errors",
        "01");
    readAt($img, blockCount($img) * SECTOR_SIZE, 1);
}

func testFindBytesLocatesAName() {
    def img as Image init writeText(formatDisk("d", "01"), "hello", FileType.Seq, "x");
    def hits as list of int init findBytes($img, encodeName("hello"));
    testing.assertEqual(len($hits), 1);
    # it is in the directory slot, at the name field
    def where as Link init blockLink($hits[0] // SECTOR_SIZE);
    testing.assertEqual($where.track, DIRECTORY_TRACK);
    testing.assertEqual($where.sector, FIRST_DIRECTORY_SECTOR);
    testing.assertEqual($hits[0] % SECTOR_SIZE, 5);
}

func testFindBytesReturnsEveryMatchInOrder() {
    def img as Image init formatDisk("d", "01");
    def mark as bytes;
    $mark[] = 0xc7;
    $mark[] = 0x2a;
    $img = writeAt($img, sectorOffset(1, 0) + 4, $mark);
    $img = writeAt($img, sectorOffset(20, 3) + 100, $mark);

    def hits as list of int init findBytes($img, $mark);
    testing.assertEqual(len($hits), 2);
    testing.assertEqual($hits[0], sectorOffset(1, 0) + 4);
    testing.assertEqual($hits[1], sectorOffset(20, 3) + 100);
}

func testFindBytesSeesAMatchAcrossAWindowBoundary() {
    # the scan works in fixed windows; a match straddling one must be found
    # exactly once, whatever the window size
    def mark as bytes;
    $mark[] = 0xc7;
    $mark[] = 0x2a;
    $mark[] = 0x5f;
    for (def offset as int init SEARCH_WINDOW - 4;
        $offset <= SEARCH_WINDOW + 1;
        $offset = $offset + 1) {
        def img as Image init writeAt(formatDisk("d", "01"), $offset, $mark);
        def hits as list of int init findBytes($img, $mark);
        testing.assertEqual(len($hits), 1);
        testing.assertEqual($hits[0], $offset);
    }
}

func testFindBytesOnAMiss() {
    def img as Image init formatDisk("d", "01");
    def mark as bytes;
    $mark[] = 0xc7;
    $mark[] = 0xc7;
    $mark[] = 0xc7;
    testing.assertEqual(len(findBytes($img, $mark)), 0);
}

func testFindBytesRejectsABadPattern() {
    testing.assertThrows("findBytesWithNothing", ERROR_KIND);
    testing.assertThrows("findBytesWithAPatternBiggerThanTheDisk", ERROR_KIND);
}

func findBytesWithNothing() {
    findBytes(formatDisk("d", "01"), zeroBytes(0));
}

func findBytesWithAPatternBiggerThanTheDisk() {
    findBytes(formatDisk("d", "01"), zeroBytes(174849));
}

func testBlockRangesStopAtTheErrorTable() {
    def img as Image init errorTableDisk();
    def all as bytes init readBlocks($img, Link{track: 1, sector: 0}, blockCount($img));
    testing.assertEqual(len($all), blockCount($img) * SECTOR_SIZE);
    # the image is longer than its blocks; the run must not reach into the table
    testing.assertTrue(len(toBytes($img)) > len($all));
    testing.assertEqual($all, toBytes($img)[0..blockCount($img) * SECTOR_SIZE]);
    testing.assertThrows("readBlocksIntoTheErrorTable", ERROR_KIND);
}

func readBlocksIntoTheErrorTable() {
    def img as Image init errorTableDisk();
    readBlocks($img, blockLink(blockCount($img) - 1), 2);
}
