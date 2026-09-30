# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the format topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testFormatNameAndBack() {
    def all as list of DiskFormat init [
        DiskFormat.Cbm,
        DiskFormat.SpeedDos,
        DiskFormat.DolphinDos,
        DiskFormat.PrologicDos
    ];
    for (def f in $all) {
        testing.assertEqual(formatFromName(formatName($f)), $f);
    }
    testing.assertEqual(formatName(DiskFormat.Cbm), "cbm");
    testing.assertEqual(formatName(DiskFormat.PrologicDos), "prologicdos");
}

func testFormatFromNameAcceptsTheSpellingsPeopleUse() {
    testing.assertEqual(formatFromName("SpeedDOS"), DiskFormat.SpeedDos);
    testing.assertEqual(formatFromName("  dolphin-dos "), DiskFormat.DolphinDos);
    testing.assertEqual(formatFromName("1541"), DiskFormat.Cbm);
    testing.assertEqual(formatFromName("commodore"), DiskFormat.Cbm);
}

func testFormatFromNameRejectsTheRest() {
    testing.assertThrows("formatFromNameOnRubbish", ERROR_KIND);
}

func formatFromNameOnRubbish() {
    formatFromName("turbodos");
}

func testFormatTracks() {
    testing.assertEqual(formatTracks(DiskFormat.Cbm), TRACKS_STANDARD);
    testing.assertEqual(formatTracks(DiskFormat.SpeedDos), TRACKS_EXTENDED);
    testing.assertEqual(formatTracks(DiskFormat.DolphinDos), TRACKS_EXTENDED);
    testing.assertEqual(formatTracks(DiskFormat.PrologicDos), TRACKS_EXTENDED);
}

func testHeaderOffsetMovesOnlyUnderPrologic() {
    testing.assertEqual(headerOffsetFor(DiskFormat.Cbm), 0x90);
    testing.assertEqual(headerOffsetFor(DiskFormat.SpeedDos), 0x90);
    testing.assertEqual(headerOffsetFor(DiskFormat.DolphinDos), 0x90);
    testing.assertEqual(headerOffsetFor(DiskFormat.PrologicDos), 0xa4);
}

func testBamEntryOffsetForTheStockTracks() {
    testing.assertEqual(bamEntryOffset(DiskFormat.Cbm, 1), 0x04);
    testing.assertEqual(bamEntryOffset(DiskFormat.Cbm, 18), 0x48);
    testing.assertEqual(bamEntryOffset(DiskFormat.Cbm, 35), 0x8c);
    # the layout does not matter below track 36
    testing.assertEqual(bamEntryOffset(DiskFormat.PrologicDos, 35), 0x8c);
}

func testBamEntryOffsetForTheExtraTracks() {
    testing.assertEqual(bamEntryOffset(DiskFormat.SpeedDos, 36), 0xc0);
    testing.assertEqual(bamEntryOffset(DiskFormat.SpeedDos, 40), 0xd0);
    testing.assertEqual(bamEntryOffset(DiskFormat.DolphinDos, 36), 0xac);
    testing.assertEqual(bamEntryOffset(DiskFormat.DolphinDos, 40), 0xbc);
    testing.assertEqual(bamEntryOffset(DiskFormat.PrologicDos, 36), 0x90);
    testing.assertEqual(bamEntryOffset(DiskFormat.PrologicDos, 40), 0xa0);
}

func testBamEntryOffsetHasNoAnswerForTracks36To42UnderCbm() {
    testing.assertEqual(bamEntryOffset(DiskFormat.Cbm, 36), -1);
    testing.assertEqual(bamEntryOffset(DiskFormat.Cbm, 40), -1);
    # no layout ever defined entries for 41 and 42
    testing.assertEqual(bamEntryOffset(DiskFormat.SpeedDos, 41), -1);
    testing.assertEqual(bamEntryOffset(DiskFormat.DolphinDos, 42), -1);
}

func testBamEntryOffsetRejectsTracksOffTheDisk() {
    testing.assertThrows("bamEntryOffsetOnTrackZero", ERROR_KIND);
}

func bamEntryOffsetOnTrackZero() {
    bamEntryOffset(DiskFormat.Cbm, 0);
}

func testBamEntriesNeverOverlapTheHeader() {
    # the point of the three layouts: five entries that fit somewhere free
    def all as list of DiskFormat init [
        DiskFormat.SpeedDos,
        DiskFormat.DolphinDos,
        DiskFormat.PrologicDos
    ];
    for (def f in $all) {
        def header as int init headerOffsetFor($f);
        for (def t as int init 36; $t <= 40; $t = $t + 1) {
            def at as int init bamEntryOffset($f, $t);
            testing.assertTrue($at + 3 < $header or $at > $header + 0x1a);
            testing.assertTrue($at + 3 < SECTOR_SIZE);
        }
    }
}

func testDefaultFormatOptions() {
    def opts as FormatOptions init defaultFormatOptions();
    testing.assertEqual($opts.tracks, TRACKS_STANDARD);
    testing.assertEqual($opts.format, DiskFormat.Cbm);
    testing.assertFalse($opts.errorInfo);
    testing.assertEqual($opts.dosType, DOS_TYPE);
}

func testFormatDiskProducesAStockDisk() {
    def img as Image init formatDisk("sample disk", "01");
    testing.assertEqual(len(toBytes($img)), 174848);
    testing.assertEqual($img.tracks, TRACKS_STANDARD);
    testing.assertEqual($img.format, DiskFormat.Cbm);
    testing.assertFalse($img.errorInfo);
    testing.assertEqual(blocksFree($img), 664);
    testing.assertEqual(len(listFiles($img)), 0);
}

func testFormatDiskWritesTheBamHeaderBytes() {
    def bam as bytes init readSector(formatDisk("sample disk", "01"), 18, 0);
    testing.assertEqual($bam[0], DIRECTORY_TRACK);
    testing.assertEqual($bam[1], FIRST_DIRECTORY_SECTOR);
    testing.assertEqual($bam[2], DOS_VERSION_BYTE);
    testing.assertEqual($bam[3], 0x00);
    # "SAMPLE DISK" then pad, $a0 $a0, the ID, $a0, "2A", four more $a0
    testing.assertEqual($bam[0x90], 0x53);
    testing.assertEqual($bam[0x9b], PAD_BYTE);
    testing.assertEqual($bam[0xa0], PAD_BYTE);
    testing.assertEqual($bam[0xa2], 0x30);
    testing.assertEqual($bam[0xa3], 0x31);
    testing.assertEqual($bam[0xa4], PAD_BYTE);
    testing.assertEqual($bam[0xa5], 0x32);
    testing.assertEqual($bam[0xa6], 0x41);
    testing.assertEqual($bam[0xaa], PAD_BYTE);
}

func testFormatDiskWritesEveryBamEntryFree() {
    def bam as bytes init readSector(formatDisk("d", "01"), 18, 0);
    # track 1: 21 sectors, bits 0-20 set
    testing.assertEqual($bam[0x04], 21);
    testing.assertEqual($bam[0x05], 0xff);
    testing.assertEqual($bam[0x06], 0xff);
    testing.assertEqual($bam[0x07], 0x1f);
    # track 18: 19 sectors less the BAM and the directory block
    testing.assertEqual($bam[0x48], 17);
    testing.assertEqual($bam[0x49], 0xfc);
    testing.assertEqual($bam[0x4b], 0x07);
    # track 35: 17 sectors, bits 0-16 set
    testing.assertEqual($bam[0x8c], 17);
    testing.assertEqual($bam[0x8f], 0x01);
}

func testFormatDiskLeavesOneEmptyDirectoryBlock() {
    def dir as bytes init readSector(formatDisk("d", "01"), 18, 1);
    testing.assertEqual($dir[0], 0x00);
    testing.assertEqual($dir[1], 0xff);
    testing.assertEqual($dir[2], 0x00);
    testing.assertEqual(len(directorySectors(formatDisk("d", "01"))), 1);
}

func testFormatDiskWithAnExtendedLayout() {
    def img as Image init speedDisk();
    testing.assertEqual(len(toBytes($img)), 196608);
    testing.assertEqual($img.tracks, TRACKS_EXTENDED);
    testing.assertEqual($img.format, DiskFormat.SpeedDos);
    # 768 blocks less the 19 on the directory track
    testing.assertEqual(blocksFree($img), 749);
    testing.assertEqual(trackBlocksFree($img, 40), 17);
}

func testAnExtendedLayoutPutsTheEntriesWhereItSaysItDoes() {
    def bam as bytes init readSector(speedDisk(), 18, 0);
    testing.assertEqual($bam[0xc0], 17);
    testing.assertEqual($bam[0xd0], 17);
    # DolphinDOS's region is untouched under SpeedDOS
    testing.assertEqual($bam[0xac], 0x00);
}

func testACbmFortyTrackDiskCannotReachTheExtraTracks() {
    def opts as FormatOptions init FormatOptions{
        tracks: TRACKS_EXTENDED,
        format: DiskFormat.Cbm,
        errorInfo: false,
        dosType: "",
        fill: 0,
        mode: FormatMode.Full
    };
    def img as Image init formatDiskWith($opts, "plain forty", "01");
    testing.assertEqual(len(toBytes($img)), 196608);
    # the five extra tracks have no BAM entry, so they are not free blocks
    testing.assertEqual(blocksFree($img), 664);
    testing.assertFalse(hasBamEntry($img, 36));
    testing.assertEqual(trackBlocksFree($img, 40), 0);
}

func testFormatDiskWithErrorInfo() {
    def opts as FormatOptions init FormatOptions{
        tracks: TRACKS_STANDARD,
        format: DiskFormat.Cbm,
        errorInfo: true,
        dosType: "",
        fill: 0,
        mode: FormatMode.Full
    };
    def img as Image init formatDiskWith($opts, "with errors", "01");
    testing.assertEqual(len(toBytes($img)), 175531);
    testing.assertTrue($img.errorInfo);
    testing.assertEqual(sectorError($img, 1, 0), ERROR_OK);
    testing.assertEqual(sectorError($img, 35, 16), ERROR_OK);
}

func testFormatDiskWithZeroFieldsTakesDefaults() {
    def img as Image init formatDiskWith(
        FormatOptions{
            tracks: 0,
            format: DiskFormat.DolphinDos,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "dolphin",
        "dd");
    testing.assertEqual($img.tracks, TRACKS_EXTENDED);
    testing.assertEqual(dosType($img), DOS_TYPE);
}

func testFormatDiskWithRejectsImpossibleOptions() {
    testing.assertThrows("formatWithOddTrackCount", ERROR_KIND);
    testing.assertThrows("formatSpeedDosOn35Tracks", ERROR_KIND);
    testing.assertThrows("formatWithALongDosType", ERROR_KIND);
    testing.assertThrows("formatWithAnEmptyName", ERROR_KIND);
    testing.assertThrows("formatWithALongId", ERROR_KIND);
}

func formatWithOddTrackCount() {
    formatDiskWith(
        FormatOptions{
            tracks: 38,
            format: DiskFormat.Cbm,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "d",
        "01");
}

func formatSpeedDosOn35Tracks() {
    formatDiskWith(
        FormatOptions{
            tracks: 35,
            format: DiskFormat.SpeedDos,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "d",
        "01");
}

func formatWithALongDosType() {
    formatDiskWith(
        FormatOptions{
            tracks: 35,
            format: DiskFormat.Cbm,
            errorInfo: false,
            dosType: "2ab",
            fill: 0,
            mode: FormatMode.Full
        },
        "d",
        "01");
}

func formatWithAnEmptyName() {
    formatDisk("", "01");
}

func formatWithALongId() {
    formatDisk("d", "012");
}

func testDetectFormatOnAStockDisk() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(detectFormat(readSector($img, 18, 0), $img.tracks), DiskFormat.Cbm);
}

func testDetectFormatRoundTripsEveryLayout() {
    def all as list of DiskFormat init [
        DiskFormat.SpeedDos,
        DiskFormat.DolphinDos,
        DiskFormat.PrologicDos
    ];
    for (def f in $all) {
        def img as Image init formatDiskWith(
            FormatOptions{
                tracks: TRACKS_EXTENDED,
                format: $f,
                errorInfo: false,
                dosType: "",
                fill: 0,
                mode: FormatMode.Full
            },
            "round trip",
            "rt");
        testing.assertEqual(fromBytes(toBytes($img)).format, $f);
    }
}

func testDetectFormatFallsBackToCbm() {
    # a 40-track image with neither extra region filled in reads as stock
    def opts as FormatOptions init FormatOptions{
        tracks: TRACKS_EXTENDED,
        format: DiskFormat.Cbm,
        errorInfo: false,
        dosType: "",
        fill: 0,
        mode: FormatMode.Full
    };
    def img as Image init formatDiskWith($opts, "plain forty", "01");
    testing.assertEqual(fromBytes(toBytes($img)).format, DiskFormat.Cbm);
}

func testReformatEmptiesTheDiskAndKeepsTheGeometry() {
    def img as Image init speedDisk();
    $img = writeText($img, "gone", FileType.Seq, "bye\n");
    testing.assertEqual(len(listFiles($img)), 1);

    def blank as Image init reformat($img, "fresh", "zz");
    testing.assertEqual(len(listFiles($blank)), 0);
    testing.assertEqual($blank.tracks, TRACKS_EXTENDED);
    testing.assertEqual($blank.format, DiskFormat.SpeedDos);
    testing.assertEqual(diskName($blank), "fresh");
    testing.assertEqual(diskId($blank), "zz");
    testing.assertEqual(blocksFree($blank), 749);
    # the image it was made from is untouched - value semantics
    testing.assertEqual(len(listFiles($img)), 1);
}

func speedDisk() {
    return formatDiskWith(
        FormatOptions{
            tracks: TRACKS_EXTENDED,
            format: DiskFormat.SpeedDos,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "speed disk",
        "sd");
}

# ------------------------------------------------------------- format modes

func testFullFormatWipesEveryBlock() {
    def img as Image init threeFiles();
    def before as bytes init readSector($img, 17, 0);
    testing.assertEqual($before[2], 0x4f);

    def blank as Image init reformat($img, "fresh", "02");
    testing.assertEqual(readSector($blank, 17, 0)[2], 0x00);
    testing.assertEqual(len(listFiles($blank)), 0);
    testing.assertEqual(blocksFree($blank), 664);
    testing.assertEqual(diskName($blank), "fresh");
    testing.assertEqual(diskId($blank), "02");
}

func testFullFormatTakesAFillByte() {
    def opts as FormatOptions init defaultFormatOptions();
    $opts.fill = 0xff;
    def img as Image init reformatWith(threeFiles(), $opts, "wiped", "02");
    # every block that is not the BAM or the directory carries the fill byte
    testing.assertEqual(readSector($img, 17, 0)[0], 0xff);
    testing.assertEqual(readSector($img, 1, 0)[255], 0xff);
    testing.assertEqual(readSector($img, 35, 16)[0], 0xff);
    # the filesystem is still written on top of it
    testing.assertEqual(blocksFree($img), 664);
    testing.assertEqual(len(listFiles($img)), 0);
    testing.assertEqual(readSector($img, DIRECTORY_TRACK, BAM_SECTOR)[2], DOS_VERSION_BYTE);
    testing.assertEqual(readSector($img, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR)[1], 0xff);
}

func testQuickFormatLeavesTheBlocksAlone() {
    def img as Image init threeFiles();
    def before as bytes init readSector($img, 17, 0);

    def quick as Image init quickFormat($img, "soft");
    testing.assertEqual(len(listFiles($quick)), 0);
    testing.assertEqual(blocksFree($quick), 664);
    testing.assertEqual(diskName($quick), "soft");
    # the old file's bytes are still there - unreachable, not erased
    testing.assertEqual(readSector($quick, 17, 0), $before);
}

func testQuickFormatKeepsTheDiskId() {
    # a real drive does not re-stamp the ID on a soft format either
    def quick as Image init quickFormat(threeFiles(), "soft");
    testing.assertEqual(diskId($quick), "01");
    testing.assertEqual(dosType($quick), DOS_TYPE);
}

func testQuickFormatFreesTheWholeDisk() {
    def img as Image init writeFile(formatDisk("d", "01"), "big", FileType.Prg, zeroBytes(6000));
    testing.assertTrue(blocksFree($img) < 664);
    def quick as Image init quickFormat($img, "d");
    testing.assertEqual(blocksFree($quick), 664);
    testing.assertTrue(isFree($quick, 17, 0));
    testing.assertFalse(isFree($quick, DIRECTORY_TRACK, BAM_SECTOR));
    testing.assertFalse(isFree($quick, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR));
}

func testQuickFormatDropsAGrownDirectory() {
    def img as Image init formatDisk("many", "01");
    for (def i as int init 0; $i < 12; $i = $i + 1) {
        $img = writeText($img, "file" + convert.toString($i), FileType.Seq, "x");
    }
    testing.assertEqual(len(directorySectors($img)), 2);
    def quick as Image init quickFormat($img, "many");
    testing.assertEqual(len(directorySectors($quick)), 1);
    testing.assertEqual(len(listFiles($quick)), 0);
}

func testFormatDiskWithTakesAFillByte() {
    def opts as FormatOptions init defaultFormatOptions();
    $opts.fill = 0x55;
    def img as Image init formatDiskWith($opts, "filled", "01");
    testing.assertEqual(readSector($img, 1, 0)[0], 0x55);
    testing.assertEqual(readSector($img, 35, 16)[255], 0x55);
    testing.assertEqual(blocksFree($img), 664);
}

func testAFillByteNeverReachesTheErrorTable() {
    def opts as FormatOptions init defaultFormatOptions();
    $opts.fill = 0xff;
    $opts.errorInfo = true;
    def img as Image init formatDiskWith($opts, "filled", "01");
    testing.assertEqual(len(toBytes($img)), 175531);
    testing.assertEqual(sectorError($img, 1, 0), ERROR_OK);
    testing.assertEqual(sectorError($img, 35, 16), ERROR_OK);
    testing.assertEqual(readSector($img, 1, 0)[0], 0xff);
}

func testReformatWithKeepsTheImageGeometry() {
    def img as Image init writeText(speedDisk(), "gone", FileType.Seq, "bye\n");
    def opts as FormatOptions init defaultFormatOptions();
    # the caller's geometry is ignored: a reformat blanks a disk, it does not
    # make a different one
    $opts.tracks = TRACKS_STANDARD;
    $opts.format = DiskFormat.Cbm;
    def blank as Image init reformatWith($img, $opts, "fresh", "sd");
    testing.assertEqual($blank.tracks, TRACKS_EXTENDED);
    testing.assertEqual($blank.format, DiskFormat.SpeedDos);
    testing.assertEqual(blocksFree($blank), 749);
    testing.assertEqual(len(listFiles($blank)), 0);
}

func testReformatRejectsABadFillByte() {
    testing.assertThrows("reformatWithABigFillByte", ERROR_KIND);
    testing.assertThrows("reformatWithANegativeFillByte", ERROR_KIND);
}

func reformatWithABigFillByte() {
    def opts as FormatOptions init defaultFormatOptions();
    $opts.fill = 256;
    reformatWith(formatDisk("d", "01"), $opts, "d", "01");
}

func reformatWithANegativeFillByte() {
    def opts as FormatOptions init defaultFormatOptions();
    $opts.fill = -1;
    formatDiskWith($opts, "d", "01");
}

func testQuickFormatRejectsAnImpossibleName() {
    testing.assertThrows("quickFormatWithALongName", ERROR_KIND);
}

func quickFormatWithALongName() {
    quickFormat(formatDisk("d", "01"), "abcdefghijklmnopq");
}

func threeFiles() {
    def img as Image init formatDisk("sample disk", "01");
    $img = writeText($img, "alpha", FileType.Seq, "one\n");
    $img = writeText($img, "beta", FileType.Prg, "two\n");
    return writeText($img, "gamma", FileType.Usr, "three\n");
}
