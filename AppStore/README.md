# AppStore — everything the product page shows

Four things make up the App Store listing. Each has one home and one script, and a
`release` deploy pushes all of them after the build lands and before `asc validate`.

| What | Lives in | Pushed by |
|---|---|---|
| Description, keywords, URLs, name | `metadata/<locale>/` | `scripts/metadata.py` |
| Screenshots | `screenshots/<locale>/<display type>/` | `scripts/screenshots.py` |
| What's New | `../german-ai-flashcards/Resources/whats_new.json` | `scripts/whats_new.py` |
| The build itself | Xcode | `scripts/deploy.py` |

```bash
python3 scripts/metadata.py check       # lengths, before Apple counts them
python3 scripts/screenshots.py check    # sizes and order
python3 scripts/whats_new.py check      # the release-notes file
```

Each script takes `push --version 1.6 [--dry-run]`, so any piece can go up on its own
without building anything. The version has to exist in App Store Connect first, and a
`release` deploy is what creates it.

## Why What's New is not in this folder

`whats_new.json` is a **resource inside the app**: the same text appears in Settings ▸
About ▸ What's New and in the sheet after an update. It has to be in the app bundle, so
it lives in `german-ai-flashcards/Resources/` and `whats_new.json` here is a symlink to
it. `scripts/deploy.py` stamps the `unreleased` entry with the shipping version and sends
that same rendered text to TestFlight and to the App Store's What's New field.

Never write that field from `metadata/`. One field with two writers is one field that
drifts. `scripts/metadata.py` deliberately has no `--whats-new`.

The workflow is in `/CLAUDE.md`: add a bullet to the `unreleased` entry whenever you ship
something a learner would notice, then `python3 scripts/whats_new.py check`.

## metadata/

One file per field. Empty or missing means **leave that field as it is** — never "clear
it", which is the safe direction for a page that is already live. Clear a field in App
Store Connect itself.

| File | Field | Limit | Scope |
|---|---|---|---|
| `description.md` | Description | 4000 | version |
| `keywords.txt` | Keywords, comma-separated | 100 | version |
| `promotional_text.txt` | The line above the fold | 170 | version |
| `marketing_url.txt` | Marketing URL | — | version |
| `support_url.txt` | Support URL | — | version |
| `name.txt` | App Store name | 30 | app info |
| `subtitle.txt` | Subtitle | 30 | app info |
| `privacy_url.txt` | Privacy policy URL | — | app info |

**Version** fields can differ per release and stay editable until the version is
approved. **App info** fields are app-wide and not tied to a version.

`description.md` is `.md` for your editor's sake only. The App Store renders **no**
formatting — headings, `**bold**` and `- bullets` would all be shown as the literal
characters you typed. Plain text, ALL-CAPS section headers, blank lines between
paragraphs. `metadata.py check` warns if Markdown syntax creeps in.

`python3 scripts/metadata.py pull --version 1.6` overwrites these files with whatever the
store currently has — useful after editing something by hand in App Store Connect, and
the way these files were first written.

## screenshots/

See `screenshots/README.md`. Sizes, ordering, and the rule that uploads are additive:
removing a file here does not remove it from the product page.

## downloaded/

Scratch space for `screenshots.py pull` (gitignored). Apple's re-encoded renditions, not
the originals — for looking at, never for re-uploading.
