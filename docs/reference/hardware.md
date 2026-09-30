<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# Drives and computers

What produced the images this deck reads, and what does not.

## Drives

| Drive | Year | Media | Capacity | Tracks | Sides | Encoding | Image |
|---|---:|---|---:|---:|---:|---|---|
| VIC-1540 | 1981 | 5¼" DD | 170 kB | 35 | 1 | GCR | **D64** |
| 1541 | 1982 | 5¼" DD | 170 kB | 35 | 1 | GCR | **D64** |
| 1570 | 1985 | 5¼" DD | 170 kB | 35 | 1 | GCR + MFM | **D64** |
| 1571 | 1985 | 5¼" DD | 340 kB | 35 ×2 | 2 | GCR + MFM | D71 |
| 1581 | 1987 | 3½" DD | 800 kB | 80 | 2 | MFM only | D81 |

Each drive is a computer: a 6502, its own RAM and ROM, and CBM DOS in
firmware. The host sends filenames and commands over the serial bus and the
drive does the rest.

**VIC-1540** - for the VIC-20. Its serial timing is too fast for the C64,
whose VIC-II steals bus cycles for video; on a C64 it works only with the
screen blanked. The 1541 ROM fixed this by slowing the transfer down.

**1541** - the same mechanism with the corrected ROM, and the drive this
deck's format belongs to. 35 tracks, 683 blocks, 664 free after formatting,
CBM DOS 2.6. Revisions: 1541 (1982), 1541C (1986), 1541-II (1988), differing
in case, power supply and track-zero detection, not in format. Notoriously
slow - about 400 bytes/s - because a hardware bug in the 6522 VIA forced
serial transfer to be done in software. Every fastloader and speeder DOS
exists to work around that.

**1570** - a single-sided 1571, sold mainly in Europe as a stopgap while
double-sided mechanisms were short. 1571 board, 1541 mechanism: burst mode,
and a WD1770/1772 controller that reads single-sided MFM disks under C128
CP/M. Its GCR side writes ordinary 35-track D64 layouts.

**1571** - the C128's drive. Double-sided, 70 tracks, 340 kB, burst mode, and
MFM through the WD1770 for CP/M and (with third-party software) MS-DOS disks.
In C64 mode it behaves as a 1541. Double-sided disks are D71, not D64.

**1581** - 3½", 800 kB, 80 tracks of 40 logical 256-byte sectors, CBM DOS
10.0, partitions and subdirectories, burst mode. MFM only, through a
WD1770/1772: it has no GCR hardware at all, so it cannot read a 1541 disk.
Images are D81.

**This deck handles D64 only** - the 1540, the 1541, the 1570, and a 1571 in
single-sided mode. D71 and D81 have different BAM and directory layouts.

## Computers

| Computer | Year | Bus | Drives |
|---|---:|---|---|
| VIC-20 | 1980 | serial IEC | 1540, 1541, 1570, 1571¹, 1581² |
| C64 | 1982 | serial IEC | 1541, 1570, 1571¹, 1581² |
| C16 | 1984 | serial IEC | 1541, 1551³, 1581² |
| Plus/4 | 1984 | serial IEC | 1541, 1551³, 1581² |
| C128 | 1985 | serial IEC + burst | 1541, 1570, 1571, 1581 |

¹ in 1541 mode, single-sided.
² at DOS level only - no low-level block access, so fastloaders and
copy-protected software do not run.
³ the 264 series' own drive: a 1541 mechanism on the parallel expansion port,
several times faster. Same D64 layout.

All five machines speak the same serial IEC bus, so any drive physically
attaches to any of them. What differs is speed and what the host software can
do with the drive beyond opening files.

**Burst mode** is a C128 feature: the 1570, 1571 and 1581 carry a CIA shift
register that transfers a byte in hardware instead of bit-banging it. On a
C64 or VIC-20 the same drives fall back to the slow serial protocol.

## GCR and MFM

Both are run-length-limited codes: a floppy stores flux reversals, not bits,
and a long run of identical bits leaves the reader with no edges to
synchronise on. Each code guarantees a maximum run at the cost of writing more
bits than it carries.

**GCR** - Group Coded Recording, what the 1540, 1541, 1570 and the 1571's
native mode use. CBM's variant encodes each 4-bit nibble as 5 bits chosen so
no more than two zeros ever run together: 4 data bytes become 5 bytes on
disk, a 25% overhead. The data is self-clocking, so no separate clock track
is needed.

The 1541 pairs GCR with **zone bit recording**. The disk spins at a constant
300 rpm and the drive writes at a constant bit rate, so the longer outer
tracks hold more sectors - four zones of 21, 19, 18 and 17 sectors. That is
where the D64 geometry comes from, and why block 683 is the last one.

**MFM** - Modified Frequency Modulation, the IBM PC and CP/M standard. A
clock bit is inserted between data bits only where the data does not supply
an edge. Constant sectors per track, so no zones. The 1571 and 1581 get it
from a Western Digital WD1770/1772 controller chip; the 1541 has no MFM
hardware.

## What a D64 is not

A D64 holds **decoded** sector payloads: 256 bytes per block and nothing else.
The GCR encoding, the sync marks, the sector header and data checksums, and
the inter-sector gaps are all stripped on the way in and regenerated on the
way out.

Anything a disk did outside the standard layout is therefore not in a D64:
non-standard sector counts, deliberately bad checksums, half-tracks,
extra-long sectors, data written in the gaps. That is most copy protection of
the era. **G64** stores the raw GCR bitstream per track and does preserve it;
this deck does not read G64.

The [error table](format.md) a D64 may carry is the one concession: it records
the read result per block, so a deliberately unreadable sector survives as a
code even though the reason for it does not.

## Sources

- [C64-Wiki](https://www.c64-wiki.com/) - drive models and revisions.
- Wikipedia: [1541](https://en.wikipedia.org/wiki/Commodore_1541),
  [1570](https://en.wikipedia.org/wiki/Commodore_1570),
  [1571](https://en.wikipedia.org/wiki/Commodore_1571),
  [1581](https://en.wikipedia.org/wiki/Commodore_1581).
- [VICE](https://vice-emu.sourceforge.io/) - D64, D71, D81 and G64 handling.
