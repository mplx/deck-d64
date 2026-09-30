#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu>
#
# Guard against the documentation drifting from the code.
#
# This replaces the deck template's check-cheatsheet.sh, which asked only
# whether every export was mentioned somewhere and answered by bare substring:
# it passed a cheatsheet naming `VERSION` only inside `DOS_VERSION_BYTE`, and
# could not see a wrong signature at all. What is checked here:
#
#   1  every `d64.X` the docs name is actually exported
#   2  documented call arity matches the code
#   3  every cheatsheet signature carries the real parameter names, in order
#   4  struct fields, enum variants and constant values match their declarations
#   5  docblock @param / @field match the declaration they sit on
#   6  relative links resolve, the book outline covers every page, and the
#      cheatsheet's layout listing matches the tree
#   7  every value a guide claims is what the code returns, every annotated
#      number is one of those values, and the directory listings the docs print
#      are byte-for-byte what directoryText emits (tools/doc-claims.j)
#
# Usage: tools/check-docs.sh
set -euo pipefail
cd "$(dirname "$0")/.."

JENNIFER="${JENNIFER:-jennifer}"

# --- 1-6: the static half ---------------------------------------------------
python3 - <<'PYSTATIC'
import re, glob, os, sys

problems = []

def note(where, what):
    problems.append(f"{where}: {what}")

# ---- the real API, from the source ----------------------------------------
funcs, consts, structs, enums, generated = {}, {}, {}, {}, set()
sources = [f for f in sorted(glob.glob('src/**/*.j', recursive=True))
           if not f.endswith('_test.j')]
for f in sources:
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(r'^export func ([A-Za-z][A-Za-z0-9]*)\(([^)]*)\)', src, re.M):
        funcs[m.group(1)] = [p.strip().split(' as ')[0].strip()
                             for p in m.group(2).split(',') if p.strip()]
    for m in re.finditer(r'^export def const ([A-Z][A-Z0-9_]*) as \w+ init ([^;]+);',
                         src, re.M):
        consts[m.group(1)] = m.group(2).strip()
        # a generated file's values are stamped in by tools/inject-version.sh,
        # so the docs describe them rather than quoting them
        if f.endswith('version.j'):
            generated.add(m.group(1))
    for m in re.finditer(r'^export def struct ([A-Za-z]\w*) \{(.*?)\};', src, re.M | re.S):
        structs[m.group(1)] = [x.strip().split(' as ')[0].strip()
                               for x in m.group(2).split(',') if x.strip()]
    for m in re.finditer(r'^export def enum ([A-Za-z]\w*) \{(.*?)\};', src, re.M | re.S):
        enums[m.group(1)] = [x.strip() for x in m.group(2).split(',') if x.strip()]

known = set(funcs) | set(consts) | set(structs) | set(enums)
for e, vs in enums.items():
    known |= {f"{e}.{v}" for v in vs}

docs = sorted(glob.glob('docs/**/*.md', recursive=True)) + ['README.md']

# ---- 1 + 2: phantom references and arity ---------------------------------
for d in docs:
    text = open(d, encoding='utf-8').read()
    for m in re.finditer(r'\bd64\.([A-Za-z][A-Za-z0-9]*)\(([^()]*)\)', text):
        name, args = m.group(1), m.group(2).strip()
        if name not in funcs:
            note(d, f"d64.{name}() is documented but not exported")
            continue
        if args == '...':          # prose, naming the call rather than making it
            continue
        got = 0 if not args else len(re.split(r',(?![^{]*\})', args))
        if got != len(funcs[name]):
            note(d, f"d64.{name}({args}) passes {got} argument(s), "
                    f"the code takes {len(funcs[name])}")
    for m in re.finditer(r'\bd64\.([A-Z][A-Za-z0-9_]*)\b(?!\()', text):
        if m.group(1) not in known:
            note(d, f"d64.{m.group(1)} is documented but not exported")

# ---- 3: cheatsheet signatures --------------------------------------------
# The API surface is tables: a signature is the first cell of a row. Only that
# cell is read, because the notes column may show a call as an example
# (`blockLink($at // SECTOR_SIZE)`), which is not a declaration. Bullets are
# still accepted so a section can be written either way.
sheet = open('docs/reference/cheatsheet.md', encoding='utf-8').read()
declared = set()
for line in sheet.split('\n'):
    if line.startswith('- '):
        cell = line
    elif line.startswith('|'):
        parts = line.split('|')
        if len(parts) < 2:
            continue
        cell = parts[1]
    else:
        continue
    for m in re.finditer(r'`([a-z][A-Za-z0-9]*)\(([^`)]*)\)`', cell):
        name, args = m.group(1), m.group(2)
        if name not in funcs:
            note('docs/reference/cheatsheet.md', f"{name}() has a signature but is not exported")
            continue
        declared.add(name)
        doc = [a.strip() for a in args.split(',') if a.strip()]
        if doc != funcs[name]:
            note('docs/reference/cheatsheet.md',
                 f"{name}({', '.join(doc)}) does not match the code's "
                 f"({', '.join(funcs[name])})")
for name in sorted(set(funcs) - declared):
    note('docs/reference/cheatsheet.md', f"{name}() has no signature in the API surface")

# ---- 4: types and constants ----------------------------------------------
def type_section(name):
    # each type is a `### `Name`` heading holding a field or variant table
    m = re.search(r'^### `' + re.escape(name) + r'`\n(.*?)(?=^#{2,3} |\Z)',
                  sheet, re.S | re.M)
    return m.group(1) if m else None

for name, fields in sorted(structs.items()):
    blk = type_section(name)
    if blk is None:
        note('docs/reference/cheatsheet.md', f"struct {name} is not described")
        continue
    for field in fields:
        if f'`{field} as' not in blk:
            note('docs/reference/cheatsheet.md', f"struct {name} field `{field}` is undocumented")
    for stale in re.findall(r'`(\w+) as ', blk):
        if stale not in fields:
            note('docs/reference/cheatsheet.md', f"struct {name} has no field `{stale}`")

for name, variants in sorted(enums.items()):
    blk = type_section(name)
    if blk is None:
        note('docs/reference/cheatsheet.md', f"enum {name} is not described")
        continue
    for v in variants:
        if f'`{v}`' not in blk:
            note('docs/reference/cheatsheet.md', f"enum {name} variant `{v}` is undocumented")

def normalise(value):
    v = value.strip().strip('`').strip('"')
    if v.startswith('$'):
        return str(int(v[1:], 16))
    if v.startswith('0x'):
        return str(int(v, 16))
    return v

rows = dict(re.findall(r'^\| `([A-Z][A-Z0-9_]*)` \| ([^|]+?) \|', sheet, re.M))
for name, value in sorted(consts.items()):
    if name not in rows:
        note('docs/reference/cheatsheet.md', f"constant {name} is not in the constants table")
    elif name not in generated and normalise(value) != normalise(rows[name]):
        note('docs/reference/cheatsheet.md',
             f"constant {name} is {value} in the code, {rows[name].strip()} in the table")
for row in sorted(set(rows) - set(consts)):
    note('docs/reference/cheatsheet.md', f"the constants table lists {row}, which is not exported")

# ---- 5: docblock drift ---------------------------------------------------
for f in sources + sorted(glob.glob('tools/*.j')) + sorted(glob.glob('examples/*.j')):
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(
            r'/\*\*(.*?)\*/\s*\n((?:export )?(?:func|def struct)[^\n{;]*)', src, re.S):
        doc, decl = m.group(1), m.group(2)
        fn = re.match(r'(?:export )?func (\w+)\(([^)]*)\)', decl)
        if fn:
            real = [p.strip().split(' as ')[0].strip()
                    for p in fn.group(2).split(',') if p.strip()]
            documented = re.findall(r'@param\s+\{[^}]*\}\s+(\w+)', doc)
            if documented != real:
                note(f, f"func {fn.group(1)}: @param {documented} "
                        f"does not match the signature {real}")
        st = re.match(r'(?:export )?def struct (\w+)', decl)
        if st:
            body = re.search(r'def struct ' + st.group(1) + r' \{(.*?)\};', src, re.S)
            real = [x.strip().split(' as ')[0].strip()
                    for x in body.group(1).split(',') if x.strip()]
            documented = re.findall(r'@field\s+\{[^}]*\}\s+(\w+)', doc)
            if documented != real:
                note(f, f"struct {st.group(1)}: @field {documented} "
                        f"does not match the fields {real}")

# ---- 6: links, outline, layout listing -----------------------------------
for d in docs:
    base = os.path.dirname(d)
    for m in re.finditer(r'\[([^\]]*)\]\(([^)#]+?)(?:#[^)]*)?\)',
                         open(d, encoding='utf-8').read()):
        target = m.group(2)
        if target.startswith(('http', 'mailto:')):
            continue
        resolved = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(resolved):
            note(d, f"link [{m.group(1)}]({target}) does not resolve")
        elif d.startswith('docs/') and not resolved.startswith('docs' + os.sep):
            # the published book is only what is under docs/, so a link that
            # walks out of it resolves in a checkout and 404s on the site
            note(d, f"link [{m.group(1)}]({target}) leaves docs/, so it works "
                    f"in a checkout but 404s on the published site")

summary = open('docs/SUMMARY.md', encoding='utf-8').read()
listed = set(re.findall(r'\]\(([^)]+)\)', summary))
present = {os.path.relpath(p, 'docs')
           for p in glob.glob('docs/**/*.md', recursive=True)} - {'SUMMARY.md'}
for orphan in sorted(present - listed):
    note('docs/SUMMARY.md', f"docs/{orphan} is not in the book outline")

where = 'docs/internal/directories.md'
listing = open(where, encoding='utf-8').read()
if '```' not in listing:
    note(where, "no source listing")
else:
    shown = set(re.findall(r'^(\S+\.j)\s', listing, re.M))
    actual = {p for p in glob.glob('src/**/*.j', recursive=True)
              if not p.endswith('_test.j')} | {'src/d64_test.j'}
    for gone in sorted(shown - actual):
        note(where, f"the source listing names {gone}, which does not exist")
    for missed in sorted(actual - shown):
        note(where, f"the source listing does not name {missed}")

if problems:
    print("", file=sys.stderr)
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    print(f"\n{len(problems)} documentation problem(s).", file=sys.stderr)
    sys.exit(1)

print(f"docs name {len(funcs)} functions, {len(structs)} structs, "
      f"{len(enums)} enums and {len(consts)} constants, all matching the code")
PYSTATIC

# --- 7: the values the guides claim ----------------------------------------
claims="$($JENNIFER run tools/doc-claims.j)"
printf '%s\n' "$claims" | sed -n '/matches the code$/p;/MISMATCH/p'

# Every integer a guide annotates a snippet with must be one of the values
# asserted by doc-claims.j. Without this a number edited in the markdown alone
# - code and assertions untouched - would go unnoticed.
python3 - "$claims" <<'PYCLAIMS'
import re, sys, glob, collections

asserted = collections.defaultdict(set)
for m in re.finditer(r'^claim (\S+) .*? => (.*)$', sys.argv[1], re.M):
    asserted[m.group(1)].add(m.group(2).strip())

bad = 0
checked = 0
for doc in sorted(glob.glob('docs/**/*.md', recursive=True)):
    for blk in re.findall(r'```jennifer\n(.*?)```',
                          open(doc, encoding='utf-8').read(), re.S):
        for line in blk.split('\n'):
            m = re.match(r'^\s*(\S.*?);\s*#\s*(.+)$', line)
            if not m or m.group(1).startswith(('def ', '$img =', 'import', 'use ')):
                continue
            lit = re.match(r'^(-?\d+)\b', m.group(2).strip())
            if not lit:
                continue          # a prose annotation, not a value
            checked += 1
            if lit.group(1) not in asserted.get(doc, set()):
                print(f"  {doc}: the snippet `{m.group(1)}` claims {lit.group(1)}, "
                      f"which tools/doc-claims.j never asserts", file=sys.stderr)
                bad += 1
if bad:
    print(f"\n{bad} of {checked} annotated value(s) are unverified.", file=sys.stderr)
    sys.exit(1)
print(f"all {checked} value(s) the guides annotate are asserted against the code")
PYCLAIMS

# Each listing doc-claims.j prints must appear verbatim in the guide it names.
python3 - "$claims" <<'PYLISTING'
import re, sys
blocks = re.findall(r'<<<listing (\S+)\n(.*?)>>>', sys.argv[1], re.S)
if not blocks:
    print("error: doc-claims.j printed no listings to compare", file=sys.stderr)
    sys.exit(1)
bad = 0
for where, listing in blocks:
    doc = open(where, encoding='utf-8').read()
    for line in [l for l in listing.split('\n') if l.strip()]:
        if line not in doc:
            print(f"  {where}: does not show the line {line!r} that "
                  f"directoryText now emits", file=sys.stderr)
            bad += 1
if bad:
    print(f"\n{bad} listing line(s) in the docs are stale.", file=sys.stderr)
    sys.exit(1)
print(f"the {len(blocks)} directory listing(s) the docs print are still exact")
PYLISTING
