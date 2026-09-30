<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# Directories

## Source

`src/d64.j` is the only compilable unit. It `use`s the libraries and
`include`s every topic, which is a textual splice: the module boundary and
every `export` is that one file. A topic cannot be linted or tested alone,
because in isolation its calls into its siblings read as undefined.

```
src/d64.j              the entry module - the one consumers import
src/d64_test.j         its white-box test overlay
src/topics/version.j   generated: VERSION, stamped from the git tag
src/topics/core.j      shared primitives: errors, buffers, bit twiddling
src/topics/geometry.j  tracks, sectors, offsets, image sizes
src/topics/petscii.j   the character set, filenames, wildcards
src/topics/format.j    the four BAM layouts, and formatting a blank disk
src/topics/image.j     the Image itself: bytes in, blocks out
src/topics/bam.j       allocation, free counts, the disk header
src/topics/directory.j the chain of 32-byte slots on track 18
src/topics/files.j     block chains: read, write, replace, scratch
```

Each `src/topics/X.j` has a co-located `X_test.j`, spliced into
`src/d64_test.j` the same way. `tools/check-overlays.sh` fails a topic
without one.

Include order matters for type declarations only: `format.j` precedes
`image.j` because `Image` has a `DiskFormat` field. Functions resolve late, so
call order is free.

## The rest

```
docs/                  the book; SUMMARY.md is the outline
examples/              one runnable example per subject, all run in CI
tools/                 the CI helpers
site/                  the built book, gitignored
```

## Generated files

Never hand-edit these; `tools/inject-version.sh` overwrites them.

| File | Holds | Stamped by |
|---|---|---|
| `src/topics/version.j` | `VERSION` | every build, from the git tags |

`deck.toml`'s `package.version` is the opposite: authored and committed,
because jvc resolves against it. See [Versioning](versioning.md).
