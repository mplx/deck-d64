# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the directory topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testFileTypeNameAndBack() {
    def all as list of FileType init [
        FileType.Del,
        FileType.Seq,
        FileType.Prg,
        FileType.Usr,
        FileType.Rel
    ];
    for (def k in $all) {
        testing.assertEqual(fileTypeFromName(fileTypeName($k)), $k);
    }
    testing.assertEqual(fileTypeName(FileType.Prg), "prg");
    testing.assertEqual(fileTypeFromName("PRG"), FileType.Prg);
    testing.assertEqual(fileTypeFromName("  seq "), FileType.Seq);
}

func testFileTypeFromNameRejectsTheRest() {
    testing.assertThrows("fileTypeFromNameOnRubbish", ERROR_KIND);
}

func fileTypeFromNameOnRubbish() {
    fileTypeFromName("dir");
}

func testFileTypeByteMatchesTheSpec() {
    testing.assertEqual(fileTypeByte(FileType.Del, false, false), 0x00);
    testing.assertEqual(fileTypeByte(FileType.Seq, true, false), 0x81);
    testing.assertEqual(fileTypeByte(FileType.Prg, true, false), 0x82);
    testing.assertEqual(fileTypeByte(FileType.Usr, true, false), 0x83);
    testing.assertEqual(fileTypeByte(FileType.Rel, true, false), 0x84);
    testing.assertEqual(fileTypeByte(FileType.Prg, true, true), 0xc2);
    testing.assertEqual(fileTypeByte(FileType.Prg, false, false), 0x02);
}

func testFileTypeFromByteReadsTheLowNibble() {
    testing.assertEqual(fileTypeFromByte(0x82), FileType.Prg);
    testing.assertEqual(fileTypeFromByte(0xc2), FileType.Prg);
    testing.assertEqual(fileTypeFromByte(0x02), FileType.Prg);
    testing.assertEqual(fileTypeFromByte(0x81), FileType.Seq);
    testing.assertEqual(fileTypeFromByte(0x00), FileType.Del);
    testing.assertEqual(fileTypeFromByte(0x80), FileType.Del);
    # 5-15 are illegal on a real drive; DEL is the safe reading
    testing.assertEqual(fileTypeFromByte(0x8f), FileType.Del);
}

func testDirectorySectorsOnAFreshDisk() {
    def chain as list of Link init directorySectors(formatDisk("d", "01"));
    testing.assertEqual(len($chain), 1);
    testing.assertEqual($chain[0].track, DIRECTORY_TRACK);
    testing.assertEqual($chain[0].sector, FIRST_DIRECTORY_SECTOR);
}

func testDirectorySectorsRefusesAChainThatLeavesTrack18() {
    testing.assertThrows("directoryChainOffTrack18", ERROR_KIND);
    testing.assertThrows("directoryChainThatLoops", ERROR_KIND);
}

func directoryChainOffTrack18() {
    def img as Image init formatDisk("d", "01");
    def block as bytes init readSector($img, 18, 1);
    $block[0] = 17;
    $block[1] = 0;
    directorySectors(writeSector($img, 18, 1, $block));
}

func directoryChainThatLoops() {
    def img as Image init formatDisk("d", "01");
    def block as bytes init readSector($img, 18, 1);
    $block[0] = DIRECTORY_TRACK;
    $block[1] = FIRST_DIRECTORY_SECTOR;
    directorySectors(writeSector($img, 18, 1, $block));
}

func testListFilesOnAFreshDisk() {
    testing.assertEqual(len(listFiles(formatDisk("d", "01"))), 0);
}

func testListFilesReadsBackWhatWasWritten() {
    def img as Image init threeFileDisk();
    def files as list of Entry init listFiles($img);
    testing.assertEqual(len($files), 3);
    testing.assertEqual($files[0].name, "alpha");
    testing.assertEqual($files[0].kind, FileType.Seq);
    testing.assertTrue($files[0].closed);
    testing.assertFalse($files[0].locked);
    testing.assertEqual($files[0].blocks, 1);
    testing.assertEqual($files[0].slot, 0);
    testing.assertEqual($files[1].name, "beta");
    testing.assertEqual($files[1].kind, FileType.Prg);
    testing.assertEqual($files[1].slot, 1);
    testing.assertEqual($files[2].name, "gamma");
    testing.assertEqual($files[2].kind, FileType.Usr);
}

func testAnEntryPointsAtItsFirstBlock() {
    def entry as Entry init findFile(threeFileDisk(), "alpha");
    testing.assertEqual($entry.track, 17);
    testing.assertEqual($entry.sector, 0);
    testing.assertEqual($entry.recordLength, 0);
}

func testHasFileIgnoresCase() {
    def img as Image init threeFileDisk();
    testing.assertTrue(hasFile($img, "alpha"));
    testing.assertTrue(hasFile($img, "ALPHA"));
    testing.assertFalse(hasFile($img, "alph"));
    testing.assertFalse(hasFile($img, "delta"));
}

func testFindFileRaisesOnAMiss() {
    testing.assertThrows("findFileOnAMiss", ERROR_KIND);
}

func findFileOnAMiss() {
    findFile(threeFileDisk(), "delta");
}

func testFindFilesMatchesPatterns() {
    def img as Image init threeFileDisk();
    testing.assertEqual(len(findFiles($img, "*")), 3);
    testing.assertEqual(len(findFiles($img, "a*")), 1);
    testing.assertEqual(len(findFiles($img, "?et?")), 1);
    testing.assertEqual(findFiles($img, "?et?")[0].name, "beta");
    testing.assertEqual(len(findFiles($img, "z*")), 0);
}

func testDirectoryTextHasAHeaderALineEachAndAFooter() {
    def listing as string init directoryText(threeFileDisk());
    def lines as list of string init strings.split($listing, "\n");
    # three files, plus the header, the footer, and the trailing empty split
    testing.assertEqual(len($lines), 6);
    testing.assertEqual($lines[0], "0 \"sample disk     \" 01 2a");
    testing.assertTrue(strings.contains($lines[1], "\"alpha\""));
    testing.assertTrue(strings.contains($lines[1], "seq"));
    testing.assertTrue(strings.contains($lines[2], "prg"));
    testing.assertEqual($lines[4], "661 blocks free.");
    testing.assertEqual($lines[5], "");
}

func testDirectoryTextMarksLockedAndSplatFiles() {
    def img as Image init lockFile(threeFileDisk(), "beta");
    testing.assertTrue(strings.contains(directoryText($img), "prg<"));

    def entry as Entry init findFile($img, "alpha");
    $entry.closed = false;
    testing.assertTrue(strings.contains(directoryText(writeEntry($img, $entry)), "*seq"));
}

func testRenameFileKeepsEverythingElse() {
    def img as Image init threeFileDisk();
    def before as Entry init findFile($img, "beta");
    $img = renameFile($img, "beta", "beta v2");
    def after as Entry init findFile($img, "beta v2");
    testing.assertFalse(hasFile($img, "beta"));
    testing.assertEqual($after.track, $before.track);
    testing.assertEqual($after.sector, $before.sector);
    testing.assertEqual($after.blocks, $before.blocks);
    testing.assertEqual($after.kind, $before.kind);
    testing.assertEqual(readText($img, "beta v2"), "two\n");
}

func testRenameToTheSameNameIsAllowed() {
    def img as Image init renameFile(threeFileDisk(), "beta", "beta");
    testing.assertTrue(hasFile($img, "beta"));
}

func testRenameRefusesACollisionAndAMiss() {
    testing.assertThrows("renameOntoAnExistingName", ERROR_KIND);
    testing.assertThrows("renameAMissingFile", ERROR_KIND);
    testing.assertThrows("renameToAnImpossibleName", ERROR_KIND);
}

func renameOntoAnExistingName() {
    renameFile(threeFileDisk(), "alpha", "beta");
}

func renameAMissingFile() {
    renameFile(threeFileDisk(), "delta", "epsilon");
}

func renameToAnImpossibleName() {
    renameFile(threeFileDisk(), "alpha", "abcdefghijklmnopq");
}

func testLockAndUnlock() {
    def img as Image init lockFile(threeFileDisk(), "beta");
    testing.assertTrue(findFile($img, "beta").locked);
    testing.assertFalse(findFile($img, "alpha").locked);

    $img = unlockFile($img, "beta");
    testing.assertFalse(findFile($img, "beta").locked);
}

func testLockRaisesOnAMiss() {
    testing.assertThrows("lockAMissingFile", ERROR_KIND);
}

func lockAMissingFile() {
    lockFile(threeFileDisk(), "delta");
}

func testTheDirectoryGrowsPastTheFirstBlock() {
    def img as Image init formatDisk("many files", "01");
    for (def i as int init 0; $i < 12; $i = $i + 1) {
        $img = writeText($img, "file" + convert.toString($i), FileType.Seq, "x");
    }
    testing.assertEqual(len(listFiles($img)), 12);
    def chain as list of Link init directorySectors($img);
    testing.assertEqual(len($chain), 2);
    # the second block is taken at the directory interleave of 3
    testing.assertEqual($chain[1].sector, FIRST_DIRECTORY_SECTOR + DIRECTORY_INTERLEAVE);
    testing.assertFalse(isFree($img, DIRECTORY_TRACK, $chain[1].sector));
    testing.assertEqual(listFiles($img)[8].slot, 8);
    testing.assertEqual(readText($img, "file11"), "x");
}

func testASlotFreedByAScratchIsUsedAgain() {
    def img as Image init threeFileDisk();
    $img = deleteFile($img, "alpha");
    testing.assertEqual(freeSlotIndex($img), 0);
    $img = writeText($img, "delta", FileType.Seq, "four\n");
    testing.assertEqual(listFiles($img)[0].name, "delta");
    testing.assertEqual(len(listFiles($img)), 3);
    testing.assertEqual(len(directorySectors($img)), 1);
}

func testFreeSlotIndexWalksTheWholeChain() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(freeSlotIndex($img), 0);
    for (def i as int init 0; $i < 8; $i = $i + 1) {
        $img = writeText($img, "file" + convert.toString($i), FileType.Seq, "x");
    }
    testing.assertEqual(freeSlotIndex($img), -1);
    $img = ensureFreeSlot($img);
    testing.assertEqual(freeSlotIndex($img), 8);
}

func testWriteEntryRejectsASlotPastTheChain() {
    testing.assertThrows("writeEntryPastTheChain", ERROR_KIND);
}

func writeEntryPastTheChain() {
    def entry as Entry init findFile(threeFileDisk(), "alpha");
    $entry.slot = 99;
    writeEntry(threeFileDisk(), $entry);
}

func threeFileDisk() {
    def img as Image init formatDisk("sample disk", "01");
    $img = writeText($img, "alpha", FileType.Seq, "one\n");
    $img = writeText($img, "beta", FileType.Prg, "two\n");
    $img = writeText($img, "gamma", FileType.Usr, "three\n");
    return $img;
}

func testTheDirectoryFillsAtOneHundredAndFortyFour() {
    def img as Image init formatDisk("full dir", "01");
    for (def i as int init 0; $i < MAX_DIRECTORY_ENTRIES; $i = $i + 1) {
        $img = writeText($img, "f" + convert.toString($i), FileType.Seq, "x");
    }
    testing.assertEqual(len(listFiles($img)), MAX_DIRECTORY_ENTRIES);
    # 18 directory blocks: every sector of track 18 but the BAM
    testing.assertEqual(len(directorySectors($img)), 18);
    testing.assertEqual(trackBlocksFree($img, DIRECTORY_TRACK), 0);
    testing.assertEqual(freeSlotIndex($img), -1);
}

func testAFullDirectoryIsRefusedNotCorrupted() {
    testing.assertThrows("writePastTheDirectoryLimit", ERROR_KIND);
}

func writePastTheDirectoryLimit() {
    def img as Image init formatDisk("full dir", "01");
    for (def i as int init 0; $i <= MAX_DIRECTORY_ENTRIES; $i = $i + 1) {
        $img = writeText($img, "f" + convert.toString($i), FileType.Seq, "x");
    }
}

# ------------------------------------------------ listings in either charset

func testDirectoryTextInRendersTheOtherReading() {
    def img as Image init borderDisk();
    def shifted as string init directoryText($img);
    def unshifted as string init directoryTextIn($img, Charset.Unshifted);

    # the same bytes, two readings: capitals one way, box drawing the other
    testing.assertTrue(strings.contains($shifted, "\"U──────I\""));
    testing.assertTrue(strings.contains($unshifted, "\"╭──────╮\""));
    # the block count, type and layout are identical either way
    testing.assertEqual(len(strings.split($shifted, "\n")), len(strings.split($unshifted, "\n")));
    testing.assertTrue(strings.contains($unshifted, "seq"));
}

func testDirectoryTextDefaultsToShifted() {
    def img as Image init borderDisk();
    testing.assertEqual(directoryText($img), directoryTextIn($img, Charset.Shifted));
}

func testTheDiskNameReadsInEitherCharset() {
    def img as Image init setDiskName(
        formatDisk("d", "01"),
        decodeNameIn(encodeNameIn("╭────╮", Charset.Unshifted), Charset.Shifted));
    testing.assertEqual(diskNameIn($img, Charset.Unshifted), "╭────╮");
    testing.assertEqual(diskName($img), "U────I");
}

func testNameBytesGivesTheRawSlotBytes() {
    def img as Image init borderDisk();
    def entry as Entry init listFiles($img)[0];
    def raw as bytes init nameBytes($img, $entry);
    testing.assertEqual(len($raw), MAX_FILENAME);
    testing.assertEqual($raw[0], 0xd5);
    testing.assertEqual($raw[7], 0xc9);
    testing.assertEqual($raw[8], PAD_BYTE);
    # the raw bytes are the lossless route to the other reading
    testing.assertEqual(decodeNameIn($raw, Charset.Unshifted), "╭──────╮");
    testing.assertEqual(decodeNameIn($raw, Charset.Shifted), $entry.name);
}

func borderDisk() {
    # a filename drawn out of border graphics, written in the unshifted set
    def img as Image init formatDisk("art disk", "01");
    def name as string init decodeNameIn(
        encodeNameIn("╭──────╮", Charset.Unshifted),
        Charset.Shifted);
    return writeText($img, $name, FileType.Seq, "x");
}
