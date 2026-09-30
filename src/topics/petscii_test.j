# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
# pragma-jennifer-version: >=0.25.0

# d64 - white-box tests for the petscii topic.
# Spliced into d64_test.j via include - run with:
#   jennifer test src/d64_test.j

func testToPetsciiSwapsCase() {
    # ASCII lower case is PETSCII's unshifted letters, which a C64 shows upper case
    def lower as bytes init toPetscii("hello");
    testing.assertEqual(len($lower), 5);
    testing.assertEqual($lower[0], 0x48);
    testing.assertEqual($lower[4], 0x4f);

    def upper as bytes init toPetscii("HELLO");
    testing.assertEqual($upper[0], 0xc8);
    testing.assertEqual($upper[4], 0xcf);
}

func testToPetsciiLeavesDigitsAndPunctuationAlone() {
    def raw as bytes init toPetscii("0 9!,:=*?");
    testing.assertEqual($raw[0], 0x30);
    testing.assertEqual($raw[1], 0x20);
    testing.assertEqual($raw[2], 0x39);
    testing.assertEqual($raw[3], 0x21);
    testing.assertEqual($raw[8], 0x3f);
}

func testToPetsciiMapsNewlineToCarriageReturn() {
    def raw as bytes init toPetscii("a\nb");
    testing.assertEqual($raw[1], 0x0d);
}

func testToPetsciiMapsTheFourPictorialGlyphs() {
    def raw as bytes init toPetscii("£↑←π");
    testing.assertEqual($raw[0], 0x5c);
    testing.assertEqual($raw[1], 0x5e);
    testing.assertEqual($raw[2], 0x5f);
    testing.assertEqual($raw[3], 0xff);
}

func testToPetsciiSubstitutesWhatItCannotSpell() {
    def raw as bytes init toPetscii('a{b}c~d€');
    testing.assertEqual(len($raw), 8);
    testing.assertEqual($raw[1], SUBSTITUTE_BYTE);
    testing.assertEqual($raw[3], SUBSTITUTE_BYTE);
    testing.assertEqual($raw[5], SUBSTITUTE_BYTE);
    testing.assertEqual($raw[7], SUBSTITUTE_BYTE);
}

func testFromPetsciiIsTheInverse() {
    def samples as list of string init [
        "hello",
        "HELLO",
        "Mixed Case 123",
        "a-b.c/d:e=f",
        "£↑←π",
        "line one\nline two\n"
    ];
    for (def s in $samples) {
        testing.assertEqual(fromPetscii(toPetscii($s)), $s);
    }
}

func testFromPetsciiHandlesTheShiftedRange() {
    def raw as bytes;
    $raw[] = 0xc1;
    $raw[] = 0x41;
    $raw[] = 0x0d;
    testing.assertEqual(fromPetscii($raw), "Aa\n");
}

func testFromPetsciiSubstitutesWhatHasNoGlyph() {
    # $80-$9f are the colour and cursor controls: no character in either set
    def raw as bytes;
    $raw[] = 0x90;
    $raw[] = 0x9f;
    testing.assertEqual(fromPetscii($raw), "??");
    testing.assertEqual(fromPetsciiIn($raw, Charset.Unshifted), "??");
}

func testTheBlockElementsReadTheSameInBothSets() {
    # $a0-$bf are not letters in either set, so they decode alike
    def raw as bytes;
    for (def b as int init 0xa1; $b <= 0xbf; $b = $b + 1) {
        $raw[] = $b;
    }
    testing.assertEqual(fromPetscii($raw), fromPetsciiIn($raw, Charset.Unshifted));
    testing.assertEqual(fromPetscii($raw)[0..1], "\u258c");
}

func testPadByteRoundTripsAsTheNoBreakSpace() {
    def raw as bytes;
    $raw[] = PAD_BYTE;
    testing.assertEqual(fromPetscii($raw), "\u00a0");
    testing.assertEqual(toPetscii("\u00a0")[0], PAD_BYTE);
}

func testEncodeNamePadsToSixteen() {
    def raw as bytes init encodeName("hello");
    testing.assertEqual(len($raw), MAX_FILENAME);
    testing.assertEqual($raw[4], 0x4f);
    testing.assertEqual($raw[5], PAD_BYTE);
    testing.assertEqual($raw[15], PAD_BYTE);
}

func testEncodeNameTakesTheFullSixteen() {
    def raw as bytes init encodeName("abcdefghijklmnop");
    testing.assertEqual(len($raw), MAX_FILENAME);
    testing.assertEqual($raw[15], 0x50);
}

func testEncodeNameRejectsWhatWillNotFit() {
    testing.assertThrows("encodeNameEmpty", ERROR_KIND);
    testing.assertThrows("encodeNameTooLong", ERROR_KIND);
    testing.assertThrows("encodeNameWithThePadByte", ERROR_KIND);
}

func encodeNameEmpty() {
    encodeName("");
}

func encodeNameTooLong() {
    encodeName("abcdefghijklmnopq");
}

func encodeNameWithThePadByte() {
    # U+00A0 is the shifted space CBM DOS pads a short name with
    encodeName("a\u00a0b");
}

func testDecodeNameTrimsThePadding() {
    testing.assertEqual(decodeName(encodeName("hello")), "hello");
    testing.assertEqual(decodeName(encodeName("abcdefghijklmnop")), "abcdefghijklmnop");
}

func testDecodeNameKeepsAnEmbeddedPadAsASpace() {
    def raw as bytes init zeroBytes(0);
    $raw[] = 0x41;
    $raw[] = PAD_BYTE;
    $raw[] = 0x42;
    $raw[] = PAD_BYTE;
    testing.assertEqual(decodeName($raw), "a b");
}

func testMatchNameOnLiterals() {
    testing.assertTrue(matchName("hello", "hello"));
    testing.assertTrue(matchName("HELLO", "hello"));
    testing.assertFalse(matchName("hello", "hell"));
    testing.assertFalse(matchName("hell", "hello"));
}

func testMatchNameWithStar() {
    testing.assertTrue(matchName("*", "anything"));
    testing.assertTrue(matchName("he*", "hello"));
    testing.assertTrue(matchName("hello*", "hello"));
    testing.assertFalse(matchName("he*", "shell"));
}

func testMatchNameWithQuestionMark() {
    testing.assertTrue(matchName("h?llo", "hello"));
    testing.assertTrue(matchName("?????", "hello"));
    testing.assertFalse(matchName("h?llo", "hllo"));
    testing.assertFalse(matchName("????", "hello"));
}

# ------------------------------------------------------------- character sets

func testTheLetterRangesDependOnTheCharset() {
    def raw as bytes;
    $raw[] = 0x48;
    $raw[] = 0xc8;
    # $48 is a letter in both sets, in opposite cases; $c8 is a letter in one
    testing.assertEqual(fromPetsciiIn($raw, Charset.Shifted), "hH");
    testing.assertEqual(fromPetsciiIn($raw, Charset.Unshifted)[0..1], "H");
    testing.assertFalse(fromPetsciiIn($raw, Charset.Unshifted)[1..2] == "H");
}

func testUnshiftedReadsTheGraphicsRange() {
    def raw as bytes;
    $raw[] = 0xd5;
    $raw[] = 0xc0;
    $raw[] = 0xc9;
    # the corners and rule a border is drawn from
    testing.assertEqual(fromPetsciiIn($raw, Charset.Unshifted), "╭─╮");
    # the same bytes are letters under the shifted reading
    testing.assertEqual(fromPetsciiIn($raw, Charset.Shifted), "U─I");
}

func testBytesSixtyToSevenFMirrorTheGraphicsRange() {
    def low as bytes;
    def high as bytes;
    for (def b as int init 0x60; $b <= 0x7f; $b = $b + 1) {
        $low[] = $b;
        $high[] = $b + 0x60;
    }
    testing.assertEqual(
        fromPetsciiIn($low, Charset.Unshifted),
        fromPetsciiIn($high, Charset.Unshifted));
    testing.assertEqual(
        fromPetsciiIn($low, Charset.Shifted),
        fromPetsciiIn($high, Charset.Shifted));
}

func testUnshiftedRoundTripsLettersAndGraphics() {
    def samples as list of string init ["HELLO", "NEWS #05", "╭──╮", "│ BORDER │", "╰──╯", "♠♥♣♦"];
    for (def s in $samples) {
        testing.assertEqual(
            fromPetsciiIn(toPetsciiIn($s, Charset.Unshifted), Charset.Unshifted),
            $s);
    }
}

func testUnshiftedHasNoLowerCaseToKeep() {
    # the hardware has no lower-case glyph there, so a lower-case letter is
    # written as its upper-case code and reads back upper case
    testing.assertEqual(
        toPetsciiIn("hello", Charset.Unshifted),
        toPetsciiIn("HELLO", Charset.Unshifted));
    testing.assertEqual(
        fromPetsciiIn(toPetsciiIn("hello", Charset.Unshifted), Charset.Unshifted),
        "HELLO");
}

func testShiftedCannotWriteTheGraphicsThatShareLetterCodes() {
    # $c1-$da are the upper-case letters in the shifted set, so a glyph that
    # lives there has nowhere to go
    testing.assertEqual(toPetsciiIn("╭", Charset.Shifted)[0], SUBSTITUTE_BYTE);
    testing.assertEqual(toPetsciiIn("╭", Charset.Unshifted)[0], 0xd5);
    # a block element outside that range writes in either set
    testing.assertEqual(toPetsciiIn("▌", Charset.Shifted)[0], 0xa1);
    testing.assertEqual(toPetsciiIn("▌", Charset.Unshifted)[0], 0xa1);
}

func testTheLegacyComputingGlyphsSurviveTheRoundTrip() {
    # several PETSCII graphics sit above U+FFFF, so four-byte UTF-8
    def raw as bytes;
    $raw[] = 0xc6;
    $raw[] = 0xc4;
    def text as string init fromPetsciiIn($raw, Charset.Unshifted);
    testing.assertEqual(len($text), 2);
    testing.assertEqual(convert.toCodepoint($text[0..1]), 0x1fb7a);
    testing.assertEqual(toPetsciiIn($text, Charset.Unshifted), $raw);
}

func testNamesEncodeAndDecodeInEitherSet() {
    def border as string init "╭──────╮";
    def raw as bytes init encodeNameIn($border, Charset.Unshifted);
    testing.assertEqual(len($raw), MAX_FILENAME);
    testing.assertEqual($raw[0], 0xd5);
    testing.assertEqual(decodeNameIn($raw, Charset.Unshifted), $border);
    # the shifted reading of the same bytes is the run of capitals
    testing.assertEqual(decodeNameIn($raw, Charset.Shifted), "U──────I");
}

func testTheDefaultsStayShifted() {
    testing.assertEqual(toPetscii("hello"), toPetsciiIn("hello", Charset.Shifted));
    def raw as bytes init toPetscii("Hello");
    testing.assertEqual(fromPetscii($raw), fromPetsciiIn($raw, Charset.Shifted));
    testing.assertEqual(encodeName("hi"), encodeNameIn("hi", Charset.Shifted));
    testing.assertEqual(
        decodeName(encodeName("hi")),
        decodeNameIn(encodeName("hi"), Charset.Shifted));
}
