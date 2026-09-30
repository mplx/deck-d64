# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the core topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testZeroBytesLength() {
    testing.assertEqual(len(zeroBytes(0)), 0);
    testing.assertEqual(len(zeroBytes(1)), 1);
    testing.assertEqual(len(zeroBytes(SECTOR_SIZE)), 256);
}

func testZeroBytesAreZero() {
    def block as bytes init zeroBytes(8);
    for (def i as int init 0; $i < len($block); $i = $i + 1) {
        testing.assertEqual($block[$i], 0);
    }
}

func testZeroBytesRejectsNegative() {
    testing.assertThrows("zeroBytesNegative", ERROR_KIND);
}

func zeroBytesNegative() {
    zeroBytes(-1);
}

func testBitSet() {
    testing.assertTrue(bitSet(0x01, 0));
    testing.assertFalse(bitSet(0x01, 1));
    testing.assertTrue(bitSet(0x80, 7));
    testing.assertTrue(bitSet(0xff, 3));
}

func testSetBitAndClearBit() {
    testing.assertEqual(setBit(0x00, 0), 0x01);
    testing.assertEqual(setBit(0x00, 7), 0x80);
    testing.assertEqual(setBit(0x81, 7), 0x81);
    testing.assertEqual(clearBit(0xff, 0), 0xfe);
    testing.assertEqual(clearBit(0xff, 7), 0x7f);
    testing.assertEqual(clearBit(0x7f, 7), 0x7f);
}

func testClearBitStaysAByte() {
    # ~(1 << b) is negative in two's complement; the mask keeps the result a byte
    for (def b as int init 0; $b < 8; $b = $b + 1) {
        testing.assertTrue(clearBit(0xff, $b) >= 0);
        testing.assertTrue(clearBit(0xff, $b) <= 0xff);
    }
}

func testBlocksForBytes() {
    # an empty file still costs the block that records "nothing used"
    testing.assertEqual(blocksForBytes(0), 1);
    testing.assertEqual(blocksForBytes(1), 1);
    testing.assertEqual(blocksForBytes(254), 1);
    testing.assertEqual(blocksForBytes(255), 2);
    testing.assertEqual(blocksForBytes(508), 2);
    testing.assertEqual(blocksForBytes(509), 3);
}

func testFailCarriesTheDeckKind() {
    testing.assertThrows("failOnce", ERROR_KIND);
}

func failOnce() {
    fail("deliberate");
}
