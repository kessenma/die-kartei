# App Store screenshots

What is in these folders is what the product page shows. `scripts/screenshots.py`
uploads them, and `scripts/deploy.py release` calls it after the build lands.

```
en-US/
  APP_IPHONE_67/          1320x2868   6.9" — the set Apple wants now
  APP_IPHONE_65/          1284x2778   6.5" — the older set, still served to older phones
  APP_IPAD_PRO_3GEN_129/  2732x2048   13" iPad (landscape)
  APP_DESKTOP/            2880x1800   Mac (16:10)
```

The folder name is the App Store display type, so nothing is guessed from a file
name. Order on the product page follows the sorted file name, which is why they
are zero-padded: `10-…` must not sort between `01-…` and `02-…`. Ten per set, max.

## Adding or replacing a screenshot

1. In Affinity, with `die-kartei-screenshots.af` open: Scripts ▸ **Export App Store
   screenshots**. Every `iphone_NN-…`, `ipad_NN-…` and `mac_NN-…` artboard goes to
   `~/Desktop/kartei-export/` (Affinity scripts can only write to the Desktop).
2. `python3 scripts/sync_screenshots.py` copies the changed files into the folders here,
   fits the 6.9" iPhone artboard into the 6.5" set, warns if the export is older than the
   `.af` file, and runs the size check. The release menu (Cmd+Opt+Shift+R) offers this step.
3. `python3 scripts/screenshots.py push --version 1.6 --dry-run` to see the plan,
   then drop `--dry-run`.

The version must already exist in App Store Connect. A `release` deploy creates it,
so the first push for a new version happens during that deploy, not before it.

## Things worth knowing

- **Uploads are additive** unless replaced. Images are matched by MD5, so an unchanged file is
  skipped and re-running costs nothing. Nothing is ever deleted: removing a file
  here does not remove it from the product page. Do that in App Store Connect, or
  with `asc screenshots delete --id … --confirm`. To swap a whole set for what is in the
  folder (needed when the new images plus the old would pass 10), use
  `release_all.py --replace-screenshots`, `screenshots.py push --replace`, or
  REPLACE_SCREENSHOTS=1 for deploy.py. That deletes the store's old images in that set.
- **An empty set folder is skipped, not emptied.** The iPad set can stay
  unfinished while the iPhone sets ship.
- **Screenshots carry forward.** App Store Connect copies the previous version's
  screenshots onto a new version, so a version starts out with the last release's
  images already attached, whether or not anything is pushed.
- `python3 scripts/screenshots.py pull --version 1.5` fetches what the store
  currently shows into `AppStore/downloaded/` (gitignored). Those are Apple's
  re-encoded renditions, not the originals — for comparing, never for re-uploading.

## Where the sources live

All screens live in one Affinity file, `../screenshots/die-kartei-screenshots.af` (one row per
screen: `iphone_NN-…`, `ipad_NN-…`, `mac_NN-…` artboards). Raw captures are in
`../screenshots/raw/{ipad,mac}/`; `../screenshots/tools/kartei-shot.sh` takes the Mac ones.
Only the exports are in the repo.
