# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - the shared primitives every other topic builds on.
# Spliced into d64.j via include - not a standalone module.

/** The `kind` every `Error` this deck raises carries. */
export def const ERROR_KIND as string init "d64";

/**
 * Raise a deck error.
 *
 * Every failure in the deck goes through here, so a caller can catch the
 * whole surface with one `kind` test. The message is written for a human:
 * it names the track, sector or file the operation was on.
 *
 * @param {string} message what went wrong, in plain words
 * @throws {Error} always, with `kind` `"d64"`
 */
func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: $message, file: "", line: 0, col: 0};
}

/**
 * A block of `n` zero bytes.
 *
 * `bytes` has no literal and no allocator, so a buffer is built by encoding a
 * run of NUL runes - one UTF-8 byte each, so the byte count equals `n`. This
 * is the one place that trick lives.
 *
 * @param {int} n how many bytes; 0 gives an empty block
 * @return {bytes} `n` zero bytes
 * @throws {Error} when `n` is negative
 */
func zeroBytes(n as int) {
    if ($n < 0) {
        fail("cannot build a block of " + convert.toString($n) + " bytes");
    }
    if ($n == 0) {
        def empty as bytes;
        return $empty;
    }
    return convert.bytesFromString(strings.repeat("\0", $n), "utf-8");
}

/**
 * Test one bit of an integer.
 *
 * @param {int} value the integer to read
 * @param {int} bit which bit, 0 = least significant
 * @return {bool} true when the bit is set
 */
func bitSet(value as int, bit as int) {
    return ($value >> $bit) & 1 == 1;
}

/**
 * Return `value` with one bit turned on.
 *
 * @param {int} value the integer to change
 * @param {int} bit which bit, 0 = least significant
 * @return {int} the new value
 */
func setBit(value as int, bit as int) {
    return $value | (1 << $bit);
}

/**
 * Return `value` with one bit turned off.
 *
 * @param {int} value the integer to change
 * @param {int} bit which bit, 0 = least significant
 * @return {int} the new value
 */
func clearBit(value as int, bit as int) {
    return $value & (~ (1 << $bit) & 0xff);
}

/**
 * The number of 254-byte data blocks a payload of `n` bytes occupies.
 *
 * CBM DOS gives even an empty file one block - the block that records "no
 * bytes used" - so the floor is 1.
 *
 * @param {int} n payload size in bytes
 * @return {int} block count, at least 1
 */
func blocksForBytes(n as int) {
    if ($n <= 0) {
        return 1;
    }
    return ($n + DATA_BYTES_PER_SECTOR - 1) // DATA_BYTES_PER_SECTOR;
}
