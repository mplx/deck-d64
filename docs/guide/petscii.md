<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# PETSCII

| Codes | ASCII | PETSCII |
|---|---|---|
| `$41`-`$5a` | `A`-`Z` | unshifted letters, shown **upper case** |
| `$61`-`$7a` | `a`-`z` | graphics |
| `$c1`-`$da` | - | shifted letters, shown **lower case** |

The mapping therefore swaps case - the `petcat` and `c1541` convention.

```jennifer
import "@mplx/d64/" as d64;

d64.toPetscii("hello");   # $48 $45 $4c $4c $4f - screen shows HELLO
d64.toPetscii("Hello");   # $c8 $45 $4c $4c $4f - screen shows hELLO
```

**Write names lower case for the classic look.** It is the only mapping under
which `fromPetscii(toPetscii(s)) == s`.

## Coverage

Exact round trip for:

- both letter cases;
- `$20`-`$40`: space, digits, `! " # $ % & ' ( ) * + , - . / : ; < = > ? @`;
- `[` and `]`;
- control codes below `$20`, passed through;
- `\n` ↔ `$0d`, the CBM line terminator, so PETSCII text splits on `\n`;
- `£` `$5c`, `↑` `$5e`, `←` `$5f`, `π` `$ff`;
- `U+00A0` ↔ `$a0`, the shifted space used as filename padding.

Everything else - `{` `}` `~` `` ` `` `_` `\` and non-Latin-1 - becomes `?`
(`SUBSTITUTE_BYTE`). No PETSCII code exists for them.

```jennifer
d64.toPetscii("a{b}");   # $41 $3f $42 $3f
```

## The two character sets

A C64 has two character ROMs, and the same byte draws different things
depending on which is selected. The ranges that differ are exactly the ones
names are made of:

| byte | `Charset.Shifted` | `Charset.Unshifted` |
|---|---|---|
| `$41`-`$5a` | `a`-`z` | `A`-`Z` |
| `$c1`-`$da` | `A`-`Z` | box drawing, shades, card suits |
| `$a0`-`$bf` | block elements | block elements |

`$60`-`$7f` mirror `$c0`-`$df`. Everything above takes `Charset.Shifted` by
default, which is the `petcat` convention.

```jennifer
def raw as bytes init d64.toPetsciiIn("╭──╮", d64.Charset.Unshifted);
d64.fromPetsciiIn($raw, d64.Charset.Unshifted);   # "╭──╮"
d64.fromPetsciiIn($raw, d64.Charset.Shifted);     # "U──I"
```

Every function that transcodes has an `...In` form taking a charset:
`toPetsciiIn`, `fromPetsciiIn`, `encodeNameIn`, `decodeNameIn`, `diskNameIn`,
`directoryTextIn`.

Two asymmetries follow from the hardware:

- **Unshifted has no lower case.** A lower-case letter is written as its
  upper-case code and reads back upper case.
- **Shifted cannot write the graphics at `$c1`-`$da`**, because those codes
  are its upper-case letters. Those glyphs substitute. The `$a0`-`$bf` block
  elements write in either set.

### Border art

Scene disks draw a frame in the directory out of those graphics. Read in the
default set it comes out as runs of capitals; read unshifted it comes out as
the border it is.

```jennifer
io.printf("%s", d64.directoryTextIn($img, d64.Charset.Unshifted));
```

`Entry.name` is always the shifted reading, and decoding is lossy for anything
PETSCII cannot spell, so `nameBytes(img, entry)` is the lossless route:

```jennifer
d64.decodeNameIn(d64.nameBytes($img, $entry), d64.Charset.Unshifted);
```

## Text only

`fromPetscii` is for names and SEQ text. `?` is lossy and irreversible - never
run program data through it.

```jennifer
d64.readFile($img, "demo");    # raw bytes
d64.readText($img, "readme");  # transcoded
```

## Filenames

16 bytes, padded with `$a0`.

```jennifer
d64.encodeName("hello");                   # $48 $45 $4c $4c $4f + 11 x $a0
d64.decodeName(d64.encodeName("hello"));   # "hello"
```

`encodeName` rejects an empty name, one over 16 characters, and one containing
the pad byte. `decodeName` drops trailing padding and turns an embedded pad
byte into a space. Every filename argument in the deck goes through
`encodeName`.

## Wildcards

```jennifer
d64.matchName("*", "anything");    # true
d64.matchName("he*", "hello");     # true
d64.matchName("h?llo", "hello");   # true
d64.matchName("hello", "hell");    # false
```

`*` matches the rest of the name and ends the pattern; anything after it is
ignored, as the drive ignores it. `?` matches one character. Case-insensitive.
`findFiles` applies this to a directory.
