# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the files topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testChainOfAnEmptyPointer() {
    testing.assertEqual(len(chainOf(formatDisk("d", "01"), 0, 0)), 0);
}

func testChainOfASingleBlockFile() {
    def img as Image init oneBlockDisk();
    def entry as Entry init findFile($img, "small");
    def chain as list of Link init chainOf($img, $entry.track, $entry.sector);
    testing.assertEqual(len($chain), 1);
    testing.assertEqual($chain[0].track, 17);
    testing.assertEqual($chain[0].sector, 0);
}

func testChainOfAMultiBlockFileFollowsTheInterleave() {
    def img as Image init writeFile(formatDisk("d", "01"), "big", FileType.Prg, counting(600));
    def entry as Entry init findFile($img, "big");
    def chain as list of Link init chainOf($img, $entry.track, $entry.sector);
    testing.assertEqual(len($chain), 3);
    testing.assertEqual($entry.blocks, 3);
    testing.assertEqual($chain[0].sector, 0);
    testing.assertEqual($chain[1].sector, 10);
    testing.assertEqual($chain[2].sector, 20);
}

func testChainOfRefusesAChainThatLoops() {
    testing.assertThrows("chainThatLoops", ERROR_KIND);
}

func chainThatLoops() {
    def img as Image init oneBlockDisk();
    def block as bytes init readSector($img, 17, 0);
    $block[0] = 17;
    $block[1] = 0;
    chainOf(writeSector($img, 17, 0, $block), 17, 0);
}

func testTheLastBlockCarriesItsLength() {
    def img as Image init writeFile(formatDisk("d", "01"), "five", FileType.Seq, counting(5));
    def block as bytes init readSector($img, 17, 0);
    testing.assertEqual($block[0], 0x00);
    testing.assertEqual($block[1], 6);
    testing.assertEqual($block[2], 0);
    testing.assertEqual($block[6], 4);
}

func testAFullBlockChainsOn() {
    def img as Image init writeFile(formatDisk("d", "01"), "full", FileType.Seq, counting(254));
    testing.assertEqual(findFile($img, "full").blocks, 1);
    testing.assertEqual(readSector($img, 17, 0)[1], 255);

    def over as Image init writeFile(formatDisk("d", "01"), "over", FileType.Seq, counting(255));
    testing.assertEqual(findFile($over, "over").blocks, 2);
    testing.assertEqual(readSector($over, 17, 0)[0], 17);
    testing.assertEqual(readSector($over, 17, 0)[1], 10);
    testing.assertEqual(readSector($over, 17, 10)[1], 2);
}

func testAnEmptyFileStillCostsOneBlock() {
    def img as Image init writeFile(formatDisk("d", "01"), "nothing", FileType.Seq, zeroBytes(0));
    testing.assertEqual(findFile($img, "nothing").blocks, 1);
    testing.assertEqual(blocksFree($img), 663);
    testing.assertEqual(len(readFile($img, "nothing")), 0);
    testing.assertEqual(readSector($img, 17, 0)[1], 1);
}

func testReadFileRoundTripsEverySize() {
    def sizes as list of int init [0, 1, 253, 254, 255, 508, 509, 600, 2000];
    for (def n in $sizes) {
        def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Prg, counting($n));
        def back as bytes init readFile($img, "blob");
        testing.assertEqual(len($back), $n);
        testing.assertEqual($back, counting($n));
    }
}

func testReadFileRaisesOnAMissAndOnACorruptEntry() {
    testing.assertThrows("readAMissingFile", ERROR_KIND);
    testing.assertThrows("readAnEntryWithNoFirstBlock", ERROR_KIND);
    testing.assertThrows("readAChainWithABadLastBlock", ERROR_KIND);
}

func readAMissingFile() {
    readFile(oneBlockDisk(), "nothere");
}

func readAnEntryWithNoFirstBlock() {
    def img as Image init oneBlockDisk();
    def entry as Entry init findFile($img, "small");
    $entry.track = 0;
    readFile(writeEntry($img, $entry), "small");
}

func readAChainWithABadLastBlock() {
    def img as Image init oneBlockDisk();
    def block as bytes init readSector($img, 17, 0);
    $block[1] = 0;
    readFile(writeSector($img, 17, 0, $block), "small");
}

func testWriteTextAndReadText() {
    def img as Image init writeText(
        formatDisk("d", "01"),
        "readme",
        FileType.Seq,
        "hello world\nsecond line\n");
    testing.assertEqual(readText($img, "readme"), "hello world\nsecond line\n");
    # stored as PETSCII: the newline is a carriage return on the disk
    testing.assertEqual(readFile($img, "readme")[11], 0x0d);
    testing.assertEqual(readFile($img, "readme")[0], 0x48);
}

func testWriteProgramAndReadProgram() {
    def img as Image init writeProgram(formatDisk("d", "01"), "hello", 2049, counting(20));
    def prg as Program init readProgram($img, "hello");
    testing.assertEqual($prg.address, 2049);
    testing.assertEqual($prg.data, counting(20));
    testing.assertEqual(findFile($img, "hello").kind, FileType.Prg);
    # the address is the first two bytes of the raw file, low byte first
    def raw as bytes init readFile($img, "hello");
    testing.assertEqual($raw[0], 0x01);
    testing.assertEqual($raw[1], 0x08);
    testing.assertEqual(len($raw), 22);
}

func testWriteProgramRejectsAnImpossibleAddress() {
    testing.assertThrows("writeProgramWithABigAddress", ERROR_KIND);
    testing.assertThrows("readProgramFromAShortFile", ERROR_KIND);
}

func writeProgramWithABigAddress() {
    writeProgram(formatDisk("d", "01"), "hello", 65536, counting(4));
}

func readProgramFromAShortFile() {
    def img as Image init writeFile(formatDisk("d", "01"), "tiny", FileType.Prg, counting(1));
    readProgram($img, "tiny");
}

func testWriteFileClaimsTheBlocksItUses() {
    def img as Image init formatDisk("d", "01");
    testing.assertEqual(blocksFree($img), 664);
    $img = writeFile($img, "big", FileType.Prg, counting(600));
    testing.assertEqual(blocksFree($img), 661);
    testing.assertFalse(isFree($img, 17, 0));
    testing.assertFalse(isFree($img, 17, 10));
    testing.assertFalse(isFree($img, 17, 20));
    testing.assertTrue(isFree($img, 17, 1));
}

func testWriteFileRefusesWhatCannotWork() {
    testing.assertThrows("writeOverAnExistingName", ERROR_KIND);
    testing.assertThrows("writeARelFile", ERROR_KIND);
    testing.assertThrows("writeADelFile", ERROR_KIND);
    testing.assertThrows("writeWithAnImpossibleName", ERROR_KIND);
}

func writeOverAnExistingName() {
    writeText(oneBlockDisk(), "small", FileType.Seq, "again");
}

func writeARelFile() {
    writeText(formatDisk("d", "01"), "records", FileType.Rel, "x");
}

func writeADelFile() {
    writeText(formatDisk("d", "01"), "ghost", FileType.Del, "x");
}

func writeWithAnImpossibleName() {
    writeText(formatDisk("d", "01"), "", FileType.Seq, "x");
}

func testWriteFileRefusesWhenTheDiskIsTooFull() {
    testing.assertThrows("writeMoreThanFits", ERROR_KIND);
}

func writeMoreThanFits() {
    # 664 blocks of 254 bytes is the most a stock disk holds
    writeFile(formatDisk("d", "01"), "toobig", FileType.Prg, zeroBytes(665 * 254));
}

func testWriteFileFillsADiskExactly() {
    def img as Image init writeFile(
        formatDisk("d", "01"),
        "everything",
        FileType.Prg,
        zeroBytes(664 * 254));
    testing.assertEqual(blocksFree($img), 0);
    testing.assertEqual(findFile($img, "everything").blocks, 664);
    testing.assertEqual(len(readFile($img, "everything")), 664 * 254);
}

func testDeleteFileGivesTheBlocksBack() {
    def img as Image init writeFile(formatDisk("d", "01"), "big", FileType.Prg, counting(600));
    $img = deleteFile($img, "big");
    testing.assertEqual(blocksFree($img), 664);
    testing.assertEqual(len(listFiles($img)), 0);
    testing.assertTrue(isFree($img, 17, 0));
    testing.assertTrue(isFree($img, 17, 20));
}

func testDeleteLeavesTheNameInTheSlot() {
    # a scratch zeroes the type byte and nothing else, which is why undelete works
    def img as Image init deleteFile(oneBlockDisk(), "small");
    def dir as bytes init readSector($img, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR);
    testing.assertEqual($dir[2], 0x00);
    testing.assertEqual($dir[3], 17);
    testing.assertEqual($dir[5], 0x53);
}

func testDeleteRefusesAMissingOrLockedFile() {
    testing.assertThrows("deleteAMissingFile", ERROR_KIND);
    testing.assertThrows("deleteALockedFile", ERROR_KIND);
}

func deleteAMissingFile() {
    deleteFile(oneBlockDisk(), "nothere");
}

func deleteALockedFile() {
    deleteFile(lockFile(oneBlockDisk(), "small"), "small");
}

func testUpdateFileReplacesTheContents() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Prg, counting(600));
    testing.assertEqual(blocksFree($img), 661);

    $img = updateFile($img, "blob", FileType.Prg, counting(10));
    testing.assertEqual(len(listFiles($img)), 1);
    testing.assertEqual(readFile($img, "blob"), counting(10));
    testing.assertEqual(findFile($img, "blob").blocks, 1);
    testing.assertEqual(blocksFree($img), 663);
}

func testUpdateFileWritesWhatIsNotThereYet() {
    def img as Image init updateFile(formatDisk("d", "01"), "new", FileType.Seq, counting(4));
    testing.assertEqual(readFile($img, "new"), counting(4));
    testing.assertEqual(len(listFiles($img)), 1);
}

func testUpdateFileCanChangeTheType() {
    def img as Image init updateFile(oneBlockDisk(), "small", FileType.Usr, counting(3));
    testing.assertEqual(findFile($img, "small").kind, FileType.Usr);
}

func testManyFilesCoexist() {
    def img as Image init formatDisk("busy", "01");
    for (def i as int init 0; $i < 20; $i = $i + 1) {
        $img = writeFile($img, "file" + convert.toString($i), FileType.Seq, counting(300 + $i));
    }
    testing.assertEqual(len(listFiles($img)), 20);
    for (def i as int init 0; $i < 20; $i = $i + 1) {
        testing.assertEqual(readFile($img, "file" + convert.toString($i)), counting(300 + $i));
    }
    # 20 files of two blocks each
    testing.assertEqual(blocksFree($img), 664 - 40);
}

func testWritesSurviveASaveAndLoadRoundTrip() {
    def img as Image init writeText(
        formatDisk("persist", "pp"),
        "readme",
        FileType.Seq,
        "still here\n");
    def again as Image init fromBytes(toBytes($img));
    testing.assertEqual(diskName($again), "persist");
    testing.assertEqual(readText($again, "readme"), "still here\n");
    testing.assertEqual(blocksFree($again), 663);
}

func testFilesLandOnTheExtraTracksOfASpeederDisk() {
    def img as Image init formatDiskWith(
        FormatOptions{
            tracks: TRACKS_EXTENDED,
            format: DiskFormat.DolphinDos,
            errorInfo: false,
            dosType: "",
            fill: 0,
            mode: FormatMode.Full
        },
        "dolphin",
        "dd");
    # fill everything but track 40, then the next file has to go there
    for (def t as int init 1; $t < TRACKS_EXTENDED; $t = $t + 1) {
        if ($t != DIRECTORY_TRACK) {
            $img = fillTrack($img, $t);
        }
    }
    testing.assertEqual(blocksFree($img), 17);
    $img = writeFile($img, "outer", FileType.Prg, counting(100));
    testing.assertEqual(findFile($img, "outer").track, 40);
    testing.assertEqual(readFile($img, "outer"), counting(100));
}

func oneBlockDisk() {
    return writeText(formatDisk("sample disk", "01"), "small", FileType.Seq, "s\n");
}

func counting(n as int) {
    def out as bytes;
    for (def i as int init 0; $i < $n; $i = $i + 1) {
        $out[] = $i % 256;
    }
    return $out;
}

# ------------------------------------------------------------- file metadata

func testFileInfoCarriesTheEntryAndTheChain() {
    def img as Image init writeFile(formatDisk("d", "01"), "big", FileType.Prg, counting(600));
    def info as FileInfo init fileInfo($img, "big");

    testing.assertEqual($info.entry.name, "big");
    testing.assertEqual($info.entry.kind, FileType.Prg);
    testing.assertTrue($info.entry.closed);
    testing.assertFalse($info.entry.locked);
    testing.assertEqual($info.entry.slot, 0);

    testing.assertEqual($info.blocks, 3);
    testing.assertEqual(len($info.chain), 3);
    testing.assertEqual($info.chain[0].track, 17);
    testing.assertEqual($info.chain[0].sector, 0);
    testing.assertEqual($info.chain[1].sector, 10);
    testing.assertEqual($info.chain[2].sector, 20);
    testing.assertTrue($info.blocksMatch);
}

func testFileInfoMeasuresTheFile() {
    def sizes as list of int init [0, 1, 253, 254, 255, 600, 2000];
    for (def n in $sizes) {
        def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Seq, counting($n));
        def info as FileInfo init fileInfo($img, "blob");
        testing.assertEqual($info.size, $n);
        testing.assertEqual($info.size, len(readFile($img, "blob")));
        testing.assertEqual($info.blocks, blocksForBytes($n));
        testing.assertEqual($info.lastUsed, $n - ($info.blocks - 1) * DATA_BYTES_PER_SECTOR);
    }
}

func testFileInfoReadsThePrgLoadAddress() {
    def img as Image init writeProgram(formatDisk("d", "01"), "demo", 0x0801, counting(20));
    testing.assertEqual(fileInfo($img, "demo").loadAddress, 2049);
    testing.assertEqual(fileInfo($img, "demo").size, 22);
}

func testFileInfoHasNoLoadAddressForOtherTypes() {
    def img as Image init writeText(formatDisk("d", "01"), "readme", FileType.Seq, "hello\n");
    testing.assertEqual(fileInfo($img, "readme").loadAddress, -1);
}

func testFileInfoHasNoLoadAddressForAShortPrg() {
    def img as Image init writeFile(formatDisk("d", "01"), "tiny", FileType.Prg, counting(1));
    testing.assertEqual(fileInfo($img, "tiny").size, 1);
    testing.assertEqual(fileInfo($img, "tiny").loadAddress, -1);
}

func testFileInfoOnAnEmptyFile() {
    def img as Image init writeFile(formatDisk("d", "01"), "nothing", FileType.Seq, zeroBytes(0));
    def info as FileInfo init fileInfo($img, "nothing");
    testing.assertEqual($info.blocks, 1);
    testing.assertEqual($info.size, 0);
    testing.assertEqual($info.lastUsed, 0);
    testing.assertTrue($info.blocksMatch);
}

func testFileInfoFlagsADirectoryThatDisagreesWithTheChain() {
    # a length the directory claims but the chain does not back up
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Prg, counting(600));
    def entry as Entry init findFile($img, "blob");
    $entry.blocks = 99;
    def info as FileInfo init fileInfo(writeEntry($img, $entry), "blob");
    testing.assertEqual($info.entry.blocks, 99);
    testing.assertEqual($info.blocks, 3);
    testing.assertFalse($info.blocksMatch);
}

func testFileInfoOnACorruptEntry() {
    def img as Image init oneBlockDisk();
    def entry as Entry init findFile($img, "small");
    $entry.track = 0;
    def info as FileInfo init fileInfo(writeEntry($img, $entry), "small");
    testing.assertEqual($info.blocks, 0);
    testing.assertEqual($info.size, 0);
    testing.assertEqual($info.loadAddress, -1);
    testing.assertFalse($info.blocksMatch);
}

func testFileInfoRaisesOnAMiss() {
    testing.assertThrows("fileInfoOnAMiss", ERROR_KIND);
}

func fileInfoOnAMiss() {
    fileInfo(oneBlockDisk(), "nothere");
}

func testListFileInfoCoversEveryFileInOrder() {
    def img as Image init formatDisk("d", "01");
    $img = writeText($img, "alpha", FileType.Seq, "one\n");
    $img = writeProgram($img, "beta", 0x1000, counting(300));
    $img = writeText($img, "gamma", FileType.Usr, "three\n");

    def all as list of FileInfo init listFileInfo($img);
    testing.assertEqual(len($all), 3);
    testing.assertEqual($all[0].entry.name, "alpha");
    testing.assertEqual($all[0].size, 4);
    testing.assertEqual($all[1].entry.name, "beta");
    testing.assertEqual($all[1].blocks, 2);
    testing.assertEqual($all[1].loadAddress, 0x1000);
    testing.assertEqual($all[2].entry.name, "gamma");
    testing.assertEqual($all[2].loadAddress, -1);

    def total as int init 0;
    for (def i in $all) {
        $total = $total + $i.blocks;
    }
    testing.assertEqual($total, 664 - blocksFree($img));
}

func testListFileInfoOnAnEmptyDisk() {
    testing.assertEqual(len(listFileInfo(formatDisk("d", "01"))), 0);
}

func testFileInfoChainMatchesChainOf() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Prg, counting(2000));
    def info as FileInfo init fileInfo($img, "blob");
    testing.assertEqual($info.chain, chainOf($img, $info.entry.track, $info.entry.sector));
}

# ------------------------------------------------------------ in-place patch

func testPatchFileChangesBytesWithoutMovingTheFile() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Prg, counting(600));
    def before as FileInfo init fileInfo($img, "blob");
    def free as int init blocksFree($img);

    def patch as bytes;
    $patch[] = 0xc7;
    $patch[] = 0x2a;
    def out as Image init patchFile($img, "blob", 10, $patch);

    def after as FileInfo init fileInfo($out, "blob");
    testing.assertEqual($after.chain, $before.chain);
    testing.assertEqual($after.size, $before.size);
    testing.assertEqual($after.entry.slot, $before.entry.slot);
    testing.assertEqual(blocksFree($out), $free);

    def raw as bytes init readFile($out, "blob");
    testing.assertEqual($raw[10], 0xc7);
    testing.assertEqual($raw[11], 0x2a);
    testing.assertEqual($raw[0..10], counting(600)[0..10]);
    testing.assertEqual($raw[12..600], counting(600)[12..600]);
}

func testPatchFileCrossesBlockBoundaries() {
    # 254 payload bytes per block, so a patch at 250 spans two of them
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Prg, counting(600));
    def patch as bytes;
    for (def i as int init 0; $i < 8; $i = $i + 1) {
        $patch[] = 0xf0 + $i;
    }
    def raw as bytes init readFile(patchFile($img, "blob", 250, $patch), "blob");
    testing.assertEqual($raw[250..258], $patch);
    testing.assertEqual($raw[249], counting(600)[249]);
    testing.assertEqual($raw[258], counting(600)[258]);
}

func testPatchFileReachesTheFirstAndLastByte() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Seq, counting(600));
    def one as bytes;
    $one[] = 0x5f;
    testing.assertEqual(readFile(patchFile($img, "blob", 0, $one), "blob")[0], 0x5f);
    testing.assertEqual(readFile(patchFile($img, "blob", 599, $one), "blob")[599], 0x5f);
}

func testPatchFileFillsAFileExactly() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Seq, counting(300));
    def replacement as bytes init counting(300);
    def out as Image init patchFile($img, "blob", 0, $replacement);
    testing.assertEqual(readFile($out, "blob"), $replacement);
}

func testPatchFileCannotChangeTheLength() {
    testing.assertThrows("patchFilePastTheEnd", ERROR_KIND);
    testing.assertThrows("patchFileWithNothing", ERROR_KIND);
    testing.assertThrows("patchFileNegative", ERROR_KIND);
    testing.assertThrows("patchFileOnAMiss", ERROR_KIND);
}

func patchFilePastTheEnd() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Seq, counting(10));
    def patch as bytes;
    $patch[] = 1;
    $patch[] = 2;
    patchFile($img, "blob", 9, $patch);
}

func patchFileWithNothing() {
    patchFile(oneBlockDisk(), "small", 0, zeroBytes(0));
}

func patchFileNegative() {
    def patch as bytes;
    $patch[] = 1;
    patchFile(oneBlockDisk(), "small", -1, $patch);
}

func patchFileOnAMiss() {
    def patch as bytes;
    $patch[] = 1;
    patchFile(oneBlockDisk(), "nothere", 0, $patch);
}

func testPatchFileLeavesOtherFilesAlone() {
    def img as Image init formatDisk("d", "01");
    $img = writeFile($img, "one", FileType.Seq, counting(400));
    $img = writeFile($img, "two", FileType.Seq, counting(400));
    def patch as bytes;
    $patch[] = 0xc7;
    def out as Image init patchFile($img, "one", 0, $patch);
    testing.assertEqual(readFile($out, "two"), counting(400));
    testing.assertEqual(readFile($out, "one")[0], 0xc7);
}

func testAFailedUpdateLeavesTheCallersImageIntact() {
    # updateFile scratches before it writes, so it is not a transaction - but
    # value semantics mean the image handed in is never the damaged one
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Seq, counting(600));
    testing.assertThrows("updateWithMoreThanFits", ERROR_KIND);
    testing.assertEqual(len(listFiles($img)), 1);
    testing.assertEqual(readFile($img, "blob"), counting(600));
    testing.assertEqual(blocksFree($img), 661);
}

func updateWithMoreThanFits() {
    def img as Image init writeFile(formatDisk("d", "01"), "blob", FileType.Seq, counting(600));
    updateFile($img, "blob", FileType.Seq, zeroBytes(665 * 254));
}

# ------------------------------------------------------- DEL entries are slots

func testReadFileRefusesADelEntry() {
    testing.assertThrows("readADelEntry", ERROR_KIND);
    testing.assertThrows("readTextOfADelEntry", ERROR_KIND);
    testing.assertThrows("readProgramOfADelEntry", ERROR_KIND);
}

func readADelEntry() {
    readFile(decoratedDisk(), "border");
}

func readTextOfADelEntry() {
    readText(decoratedDisk(), "border");
}

func readProgramOfADelEntry() {
    readProgram(decoratedDisk(), "border");
}

func testDelEntriesReportNoChain() {
    # the pointer in a DEL slot names no file, so it is not followed
    def info as FileInfo init fileInfo(decoratedDisk(), "border");
    testing.assertEqual($info.entry.kind, FileType.Del);
    testing.assertEqual($info.blocks, 0);
    testing.assertEqual(len($info.chain), 0);
    testing.assertEqual($info.size, 0);
    testing.assertEqual($info.loadAddress, -1);
    # nothing to disagree about: the entry records 0 blocks and 0 were walked
    testing.assertTrue($info.blocksMatch);
}

func testScratchingADelEntryFreesNothing() {
    # the decorative entry points at 18/0; following it would hand the BAM and
    # the directory back to the allocator as free space
    def img as Image init decoratedDisk();
    def free as int init blocksFree($img);
    def files as int init len(listFiles($img));

    def out as Image init deleteFile($img, "border");
    testing.assertEqual(blocksFree($out), $free);
    testing.assertEqual(len(listFiles($out)), $files - 1);
    testing.assertFalse(hasFile($out, "border"));
    # the BAM and the directory are still allocated, and the real file is intact
    testing.assertFalse(isFree($out, DIRECTORY_TRACK, BAM_SECTOR));
    testing.assertFalse(isFree($out, DIRECTORY_TRACK, FIRST_DIRECTORY_SECTOR));
    testing.assertEqual(readFile($out, "real"), counting(300));
}

func testAScratchedRealFileStillFreesItsBlocks() {
    # the DEL rule must not have disarmed the ordinary path
    def img as Image init decoratedDisk();
    def before as int init blocksFree($img);
    def out as Image init deleteFile($img, "real");
    testing.assertEqual(blocksFree($out), $before + 2);
}

func testListFileInfoSurvivesADecoratedDirectory() {
    def all as list of FileInfo init listFileInfo(decoratedDisk());
    testing.assertEqual(len($all), 2);
    for (def info in $all) {
        testing.assertTrue($info.blocksMatch);
    }
}

func decoratedDisk() {
    # a disk shaped like the scene disks: one real file and one DEL entry used
    # as directory art, its first-block pointer left at the BAM
    def img as Image init formatDisk("decorated", "01");
    $img = writeFile($img, "real", FileType.Seq, counting(300));
    $img = writeFile($img, "border", FileType.Seq, counting(1));
    def entry as Entry init findFile($img, "border");
    def owned as Link init Link{track: $entry.track, sector: $entry.sector};
    $entry.kind = FileType.Del;
    $entry.track = DIRECTORY_TRACK;
    $entry.sector = BAM_SECTOR;
    $entry.blocks = 0;
    $img = writeEntry($img, $entry);
    # give back the block the entry owned before it became art, so the disk is
    # consistent the way a mastering tool would leave it
    return freeSector($img, $owned.track, $owned.sector);
}
