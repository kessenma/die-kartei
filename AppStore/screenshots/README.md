# App Store screenshots

What is in these folders is what the product page shows. `scripts/screenshots.py`
uploads them, and `scripts/deploy.py release` calls it after the build lands.

```
en-US/
  APP_IPHONE_67/          1320x2868   6.9" — the set Apple wants now
  APP_IPHONE_65/          1284x2778   6.5" — the older set, still served to older phones
  APP_IPAD_PRO_3GEN_129/  2048x2732   13" iPad
```

The folder name is the App Store display type, so nothing is guessed from a file
name. Order on the product page follows the sorted file name, which is why they
are zero-padded: `10-…` must not sort between `01-…` and `02-…`. Ten per set, max.

## Adding or replacing a screenshot

1. Export from Affinity at the exact size the folder expects. Anything else is
   rejected — `python3 scripts/screenshots.py check` tells you before Apple does.
2. Drop it in, named `NN-what-it-shows.jpg`.
3. `python3 scripts/screenshots.py push --version 1.6 --dry-run` to see the plan,
   then drop `--dry-run`.

The version must already exist in App Store Connect. A `release` deploy creates it,
so the first push for a new version happens during that deploy, not before it.

## Things worth knowing

- **Uploads are additive.** Images are matched by MD5, so an unchanged file is
  skipped and re-running costs nothing. Nothing is ever deleted: removing a file
  here does not remove it from the product page. Do that in App Store Connect, or
  with `asc screenshots delete --id … --confirm`.
- **An empty set folder is skipped, not emptied.** The iPad set can stay
  unfinished while the iPhone sets ship.
- **Screenshots carry forward.** App Store Connect copies the previous version's
  screenshots onto a new version, so a version starts out with the last release's
  images already attached, whether or not anything is pushed.
- `python3 scripts/screenshots.py pull --version 1.5` fetches what the store
  currently shows into `AppStore/downloaded/` (gitignored). Those are Apple's
  re-encoded renditions, not the originals — for comparing, never for re-uploading.

## Where the sources live

The Affinity documents are in `~/Desktop/AppStore screen shots` (`.af` files and
`raw-screens/`). They are not in the repo; only the exports are.
