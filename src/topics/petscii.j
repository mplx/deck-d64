# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - PETSCII: the character set CBM DOS stores names and text in.
# Spliced into d64.j via include - not a standalone module.

/** The byte CBM DOS pads a short name with: shifted space. */
export def const PAD_BYTE as int init 0xa0;

/** The byte an unmappable character becomes: PETSCII `?`. */
export def const SUBSTITUTE_BYTE as int init 0x3f;

/** The longest filename CBM DOS stores. */
export def const MAX_FILENAME as int init 16;

/**
 * Which of the C64's two character sets a PETSCII byte is read in.
 *
 * The same byte draws different things depending on which character ROM the
 * machine has selected, and the ranges that differ are exactly the ones names
 * are made of:
 *
 *   byte       `Shifted` (lower/upper)   `Unshifted` (upper/graphics)
 *   `$41`-`$5a`  a-z                       A-Z
 *   `$c1`-`$da`  A-Z                       box drawing, suits, shades
 *
 * `$a0`-`$bf` are the same block elements in both. Bytes `$60`-`$7f` mirror
 * `$c0`-`$df`.
 *
 * The zero value is `Shifted`, the convention `petcat` uses and the one the
 * plain {@link toPetscii} / {@link fromPetscii} keep.
 */
export def enum Charset {
    Shifted,
    Unshifted
};

/**
 * Unicode code points for PETSCII `$a0`-`$df`, the graphics range.
 *
 * Indexed by `byte - $a0`. Under `Charset.Shifted` the slice `$c1`-`$da` is
 * overridden by the letters; everything else here reads the same in both
 * character sets. Several glyphs live in Unicode's Symbols for Legacy
 * Computing block, above `U+FFFF`.
 */
def const GRAPHICS as list of int init [
    0x00a0,
    0x258c,
    0x2584,
    0x2594,
    0x2581,
    0x258f,
    0x2592,
    0x2595,
    0x1fb8f,
    0x25e4,
    0x1fb87,
    0x251c,
    0x2597,
    0x2514,
    0x2510,
    0x2582,
    0x250c,
    0x2534,
    0x252c,
    0x2524,
    0x258e,
    0x258d,
    0x1fb88,
    0x1fb82,
    0x1fb83,
    0x2583,
    0x1fb7f,
    0x2596,
    0x259d,
    0x2518,
    0x2598,
    0x259a,
    0x2500,
    0x2660,
    0x1fb72,
    0x1fb78,
    0x1fb77,
    0x1fb76,
    0x1fb7a,
    0x1fb71,
    0x1fb74,
    0x256e,
    0x2570,
    0x256f,
    0x1fb7c,
    0x2572,
    0x2571,
    0x1fb7d,
    0x1fb7e,
    0x2022,
    0x1fb7b,
    0x2665,
    0x1fb70,
    0x256d,
    0x2573,
    0x25cb,
    0x2663,
    0x1fb75,
    0x2666,
    0x253c,
    0x1fb8c,
    0x2502,
    0x03c0,
    0x25e5
];

/**
 * Transcode text to PETSCII, reading it in the lower/upper character set.
 *
 * {@link toPetsciiIn} with `Charset.Shifted`: the convention `petcat` and
 * `c1541` use, under which `toPetscii("hello")` gives the bytes a C64 shows
 * as `HELLO`.
 *
 * @param {string} text the text to transcode
 * @return {bytes} the PETSCII bytes
 * @example
 *   toPetscii("hello");   # $48 $45 $4c $4c $4f
 *   toPetscii("Hi");      # $c8 $49
 */
export func toPetscii(text as string) {
    return toPetsciiIn($text, Charset.Shifted);
}

/**
 * Transcode text to PETSCII in a chosen character set.
 *
 * PETSCII and ASCII agree on the digits, the space and the punctuation. The
 * letters depend on the character set: see {@link Charset}.
 *
 * Under `Unshifted` there is no lower case to store, so a lower-case letter
 * is written as its upper-case code and reads back upper case. Under
 * `Shifted` the graphics at `$c1`-`$da` have no byte to live in, because
 * those codes are the upper-case letters, so those glyphs substitute.
 *
 * Three C64 glyphs outside the graphics range are accepted as their Unicode
 * characters in both sets: `£` (`$5c`), `↑` (`$5e`) and `←` (`$5f`); `π` maps
 * to `$ff`. A newline becomes the CBM line terminator `$0d`. Anything with no
 * PETSCII code at all becomes {@link SUBSTITUTE_BYTE}.
 *
 * @param {string}  text    the text to transcode
 * @param {Charset} charset which character set to write it in
 * @return {bytes} the PETSCII bytes
 * @example
 *   toPetsciiIn("HELLO", Charset.Unshifted);   # $48 $45 $4c $4c $4f
 *   toPetsciiIn("╭──╮", Charset.Unshifted);    # $d5 $c0 $c0 $c9
 */
export func toPetsciiIn(text as string, charset as Charset) {
    def out as bytes;
    for (def ch in strings.chars($text)) {
        $out[] = petsciiFromCodepoint(convert.toCodepoint($ch), $charset);
    }
    return $out;
}

/**
 * Transcode PETSCII bytes to text, reading them in the lower/upper set.
 *
 * {@link fromPetsciiIn} with `Charset.Shifted`, the inverse of
 * {@link toPetscii}.
 *
 * @param {bytes} data the PETSCII bytes
 * @return {string} the text
 * @example
 *   fromPetscii(toPetscii("hello"));   # "hello"
 */
export func fromPetscii(data as bytes) {
    return fromPetsciiIn($data, Charset.Shifted);
}

/**
 * Transcode PETSCII bytes to text in a chosen character set.
 *
 * `Unshifted` is how a directory full of border art is meant to be read: the
 * codes a `Shifted` reading turns into runs of capitals are box drawing,
 * shades and card suits. `$a0`-`$bf` are the same block elements either way,
 * and `$60`-`$7f` mirror `$c0`-`$df`.
 *
 * A byte with no glyph in the chosen set - the colour and cursor controls -
 * becomes `?`.
 *
 * This is a text conversion, not a byte-preserving one: use it on names and
 * on SEQ text, never on program data. {@link readFile} hands back raw bytes
 * for that.
 *
 * @param {bytes}   data    the PETSCII bytes
 * @param {Charset} charset which character set to read them in
 * @return {string} the text
 * @example
 *   fromPetsciiIn($raw, Charset.Unshifted);   # "╭──╮" where Shifted says "UPPN"
 */
export func fromPetsciiIn(data as bytes, charset as Charset) {
    # Build UTF-8 and decode once: `$out = $out + ch` would rebuild the whole
    # string per byte, and a string per character costs a call and an
    # allocation each. The graphics range reaches Unicode's Symbols for Legacy
    # Computing, above U+FFFF, so all four UTF-8 lengths can arise.
    def buf as bytes;
    for (def i as int init 0; $i < len($data); $i = $i + 1) {
        def cp as int init codepointFromPetscii($data[$i], $charset);
        if ($cp < 0x80) {
            $buf[] = $cp;
        } elseif ($cp < 0x800) {
            $buf[] = 0xc0 | ($cp >> 6);
            $buf[] = 0x80 | ($cp & 0x3f);
        } elseif ($cp < 0x10000) {
            $buf[] = 0xe0 | ($cp >> 12);
            $buf[] = 0x80 | (($cp >> 6) & 0x3f);
            $buf[] = 0x80 | ($cp & 0x3f);
        } else {
            $buf[] = 0xf0 | ($cp >> 18);
            $buf[] = 0x80 | (($cp >> 12) & 0x3f);
            $buf[] = 0x80 | (($cp >> 6) & 0x3f);
            $buf[] = 0x80 | ($cp & 0x3f);
        }
    }
    return convert.stringFromBytes($buf, "utf-8");
}

/**
 * Encode a filename into the 16 bytes a directory entry holds.
 *
 * {@link encodeNameIn} with `Charset.Shifted`.
 *
 * @param {string} name the filename, 1 to 16 characters
 * @return {bytes} 16 PETSCII bytes
 * @throws {Error} when the name is empty, too long, or contains the pad byte
 * @example
 *   encodeName("hello");   # $48 $45 $4c $4c $4f then 11 x $a0
 */
export func encodeName(name as string) {
    return encodeNameIn($name, Charset.Shifted);
}

/**
 * Encode a filename in a chosen character set.
 *
 * `Charset.Unshifted` is what writes a name made of border graphics.
 *
 * @param {string}  name    the filename, 1 to 16 characters
 * @param {Charset} charset which character set to write it in
 * @return {bytes} 16 PETSCII bytes, padded with {@link PAD_BYTE}
 * @throws {Error} when the name is empty, too long, or contains the pad byte
 * @example
 *   encodeNameIn("╭──────────────╮", Charset.Unshifted);
 */
export func encodeNameIn(name as string, charset as Charset) {
    def encoded as bytes init toPetsciiIn($name, $charset);
    if (len($encoded) == 0) {
        fail("a filename cannot be empty");
    }
    if (len($encoded) > MAX_FILENAME) {
        fail("filename \"" + $name + "\" is longer than 16 characters");
    }
    for (def i as int init 0; $i < len($encoded); $i = $i + 1) {
        if ($encoded[$i] == PAD_BYTE) {
            fail("filename \"" + $name + "\" contains the shifted space CBM DOS pads with");
        }
    }
    def out as bytes init $encoded;
    for (def i as int init len($encoded); $i < MAX_FILENAME; $i = $i + 1) {
        $out[] = PAD_BYTE;
    }
    return $out;
}

/**
 * Decode the 16 name bytes of a directory entry, in the lower/upper set.
 *
 * {@link decodeNameIn} with `Charset.Shifted`.
 *
 * @param {bytes} raw the 16 name bytes
 * @return {string} the filename
 * @example
 *   decodeName(encodeName("hello"));   # "hello"
 */
export func decodeName(raw as bytes) {
    return decodeNameIn($raw, Charset.Shifted);
}

/**
 * Decode the 16 name bytes of a directory entry in a chosen character set.
 *
 * Trailing pad bytes are dropped; a pad byte in the middle of a name is kept
 * as a space, because some mastering tools write names that way.
 *
 * @param {bytes}   raw     the 16 name bytes
 * @param {Charset} charset which character set to read them in
 * @return {string} the filename
 * @example
 *   decodeNameIn(nameBytes($img, $entry), Charset.Unshifted);
 */
export func decodeNameIn(raw as bytes, charset as Charset) {
    def end as int init len($raw);
    while ($end > 0 and $raw[$end - 1] == PAD_BYTE) {
        $end = $end - 1;
    }
    def out as list of string;
    for (def i as int init 0; $i < $end; $i = $i + 1) {
        if ($raw[$i] == PAD_BYTE) {
            $out[] = " ";
        } else {
            $out[] = convert.fromCodepoint(codepointFromPetscii($raw[$i], $charset));
        }
    }
    return strings.join($out, "");
}

/**
 * One Unicode code point as one PETSCII byte.
 *
 * Ordered by how often each case comes up, not by how interesting it is: this
 * runs once per character and the letter and punctuation ranges are almost all
 * of any real text.
 *
 * @param {int}     cp      the code point
 * @param {Charset} charset which character set to write it in
 * @return {int} the PETSCII byte, or {@link SUBSTITUTE_BYTE}
 */
func petsciiFromCodepoint(cp as int, charset as Charset) {
    if ($cp >= 0x61 and $cp <= 0x7a) {
        # a-z is $41-$5a in both sets; Unshifted has no lower case to keep
        return $cp - 0x20;
    }
    if ($cp >= 0x20 and $cp <= 0x40) {
        return $cp;
    }
    if ($cp >= 0x41 and $cp <= 0x5a) {
        if ($charset == Charset.Unshifted) {
            return $cp;
        }
        return $cp + 0x80;
    }
    if ($cp == 0x5b or $cp == 0x5d) {
        return $cp;
    }
    if ($cp == 0x0a) {
        return 0x0d;
    }
    if ($cp == 0xa0) {
        return PAD_BYTE;
    }
    if ($cp == 0xa3) {
        return 0x5c;
    }
    if ($cp == 0x2191) {
        return 0x5e;
    }
    if ($cp == 0x2190) {
        return 0x5f;
    }
    if ($cp == 0x03c0) {
        return 0xff;
    }
    if ($cp < 0x20) {
        return $cp;
    }
    return graphicByte($cp, $charset);
}

/**
 * The PETSCII byte that draws a graphics glyph, or the substitute.
 *
 * Scanned rather than looked up: this runs only for a code point that is not
 * text, which is rare enough that a 64-entry walk costs nothing.
 *
 * @param {int}     cp      the code point
 * @param {Charset} charset which character set to write it in
 * @return {int} the PETSCII byte, or {@link SUBSTITUTE_BYTE}
 */
func graphicByte(cp as int, charset as Charset) {
    for (def i as int init 0; $i < len(GRAPHICS); $i = $i + 1) {
        if (GRAPHICS[$i] == $cp) {
            def b as int init 0xa0 + $i;
            if ($charset == Charset.Shifted and $b >= 0xc1 and $b <= 0xda) {
                # those codes are the upper-case letters here, so the glyph
                # has nowhere to go
                return SUBSTITUTE_BYTE;
            }
            return $b;
        }
    }
    return SUBSTITUTE_BYTE;
}

/**
 * One PETSCII byte as one Unicode code point.
 *
 * Frequency-ordered, like its inverse. `$0d` must precede the control-code
 * catch-all; the letter ranges must precede the graphics table, which is what
 * the two character sets disagree about.
 *
 * @param {int}     b       the PETSCII byte
 * @param {Charset} charset which character set to read it in
 * @return {int} the code point, or `?` when the byte has no glyph
 */
func codepointFromPetscii(b as int, charset as Charset) {
    def code as int init $b;
    if ($code >= 0x60 and $code <= 0x7f) {
        # $60-$7f draw the same glyphs as $c0-$df
        $code = $code + 0x60;
    }
    if ($code >= 0x41 and $code <= 0x5a) {
        if ($charset == Charset.Unshifted) {
            return $code;
        }
        return $code + 0x20;
    }
    if ($code >= 0x20 and $code <= 0x40) {
        return $code;
    }
    if ($code >= 0xc1 and $code <= 0xda and $charset == Charset.Shifted) {
        return $code - 0x80;
    }
    if ($code == 0x5b or $code == 0x5d) {
        return $code;
    }
    if ($code == 0x0d) {
        return 0x0a;
    }
    if ($code == 0x5c) {
        return 0xa3;
    }
    if ($code == 0x5e) {
        return 0x2191;
    }
    if ($code == 0x5f) {
        return 0x2190;
    }
    if ($code == 0xff) {
        return 0x03c0;
    }
    if ($code >= 0xa0 and $code <= 0xdf) {
        return GRAPHICS[$code - 0xa0];
    }
    if ($code < 0x20) {
        return $code;
    }
    return SUBSTITUTE_BYTE;
}

/**
 * Match a filename against a CBM DOS pattern.
 *
 * `*` matches the rest of the name and ends the pattern - that is how the
 * drive reads it, so `he*lo` matches every name starting `he`. `?` matches
 * exactly one character. The comparison is case-insensitive, because a
 * PETSCII name has only one case on screen.
 *
 * @param {string} pattern the pattern, `*` and `?` recognised
 * @param {string} name    the filename to test
 * @return {bool} true when the name matches
 * @example
 *   matchName("he*", "hello");     # true
 *   matchName("h?llo", "hello");   # true
 *   matchName("hello", "hell");    # false
 */
export func matchName(pattern as string, name as string) {
    def p as list of string init strings.chars(strings.lower($pattern));
    def n as list of string init strings.chars(strings.lower($name));
    for (def i as int init 0; $i < len($p); $i = $i + 1) {
        if ($p[$i] == "*") {
            return true;
        }
        if ($i >= len($n)) {
            return false;
        }
        if ($p[$i] != "?" and $p[$i] != $n[$i]) {
            return false;
        }
    }
    return len($p) == len($n);
}
