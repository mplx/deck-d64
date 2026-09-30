<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <developer@mplx.eu> -->

# Versioning

A version lives in two places, and only one of them is generated.

| Where | Authored or generated | Who reads it |
|---|---|---|
| `deck.toml` `package.version` | **authored, committed** | jvc, and `pack.sh` for the archive name |
| `src/topics/version.j` `VERSION` | generated per build | the deck at runtime |

`deck.toml` has to be committed because jvc resolves against the manifest on
the default branch: `package.urls.deck` points at
`raw.githubusercontent.com/.../main/deck.toml`. A version that existed only
inside a CI workspace would leave jvc resolving whatever was last committed.

`src/topics/version.j` is derived from the git tags, so `d64.VERSION` says
which build a copy came from.

## Forms

What `tools/version.sh` derives, and what gets stamped into `version.j`:

| HEAD | Version |
|---|---|
| stable tag `0.2.0` or `v0.2.0` | `0.2.0` |
| 14 commits past `0.2.0` | `0.2.0-dev+14.9ebf3dd` |
| no stable tag in history | `<manifest version>-dev+<commits>.<sha>` |
| no commit yet, or not a git checkout | the `deck.toml` value |

`<commits>.<sha>` is the commit count since the anchor tag and the 7-character
commit id - the form `jennifer version` prints.

A tag carrying a prerelease or build suffix (`0.3.0-rc1`) is not a release: it
does not anchor a dev version and `release.yml` rejects it.

Build metadata after `+` is ignored by semver precedence, so
`0.2.0-dev+14.9ebf3dd` orders before `0.2.0`.

## Scripts

```sh
tools/version.sh              # print the derived version
tools/inject-version.sh       # stamp it into src/topics/version.j
tools/inject-version.sh 1.2.3 # stamp an explicit version
```

`inject-version.sh` rejects a non-semver argument and never touches
`deck.toml`. Edits to `src/topics/version.j` are overwritten.

## Releasing

1. Bump `version` in `deck.toml` and commit it.
2. Tag the same number: `git tag 0.2.0` (or `v0.2.0`) and push it.

`release.yml` refuses a tag that disagrees with the manifest, so the two
cannot drift.

## At runtime

```jennifer
import "@mplx/d64/" as d64;

d64.VERSION;   # "0.2.0"
```

## CI

| Workflow | Trigger | Does |
|---|---|---|
| `test.yml` | every commit, every branch, every PR | inject version, fmt, lint, guards, suites, examples, `jennifer-tiny` |
| `docs.yml` | every commit and PR | build the book; publish to Pages from `main` |
| `release.yml` | stable version tag | the same gate, then pack and release |

`test.yml` injects before `fmt`, so the generated file is linted and
header-checked like any other source. `release.yml` injects and fails when the
result disagrees with the tag being built.
