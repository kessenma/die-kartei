# Deploy setup — getting a new Mac from zero to shipping

Die Kartei deploys through the [App Store Connect CLI](https://github.com/rorkai/App-Store-Connect-CLI)
(`asc`), driven by [`scripts/deploy.py`](../scripts/deploy.py).

Follow this top to bottom on a machine that has never deployed this app. Budget
~20 minutes, most of it Xcode downloading.

> **The Xcode/SDK that builds the binary must be a released version, and the
> binary must not *say* it was built on a beta macOS.** App Store Connect accepts
> both kinds on *upload* and rejects them at *submission* with the same
> ITMS-90111 ("Unsupported SDK or Xcode version"). `deploy.py` aborts before
> archiving if a beta Xcode is selected. A beta *host* macOS is fine: the
> target's last build phase, "Stamp release macOS build"
> (`scripts/stamp-release-os.sh`), rewrites the `BuildMachineOSBuild` stamp to a
> public release before code signing, and `deploy.py` refuses to archive on a
> beta host if that phase has gone missing. Xcode's GUI is never needed.
>
> Deploying uses `xcodebuild` only — the Xcode GUI is never opened. A machine
> where the Xcode app refuses to launch can still ship perfectly well, as long as
> `xcodebuild -version` reports a released version and signing is set up per
> section 4. See Troubleshooting if the GUI won't open.

---

## App identity

Values you'll see referenced throughout. None of these are secret.

| | |
|---|---|
| App name | Die Kartei |
| App Store Connect app ID | `6770390331` |
| Bundle ID | `kyle-essenmacher.german-ai-flashcards` |
| Apple team ID | `RHPLRY9X9P` |
| ASC API key ID | `24JDJGBV9T` |
| ASC issuer ID | `5e67a835-18f8-47a8-aa06-e1a43e9c5c44` |
| TestFlight groups | `internal-die-Kartei`, `external-die-Kartei` |

---

## Already set up? Start here

Sections 1–4 are one-time-per-machine. To find out whether this machine is
already done, run:

```bash
asc auth status --validate    # "validation":"works"  -> sections 1-3 done
asc doctor                    # exits 0
security find-identity -v -p codesigning | grep "Apple Distribution"
                              # a match -> section 4 done
xcodebuild -version           # must not say "beta"
sw_vers -buildVersion         # a trailing letter (26A5421a) = beta host; OK, see note above
```

All four clean means you can skip to **[section 6, Ship](#6-ship)**.

**The primary dev Mac (macOS 27 beta) is already set up** — `asc` installed and
authenticated, and the signing certificate and App Store profile both present. Its
Xcode *GUI* cannot launch, which does not prevent deploying; see Troubleshooting.

---

## 1. Prerequisites

- **Xcode, released build** — from the Mac App Store, or
  [developer.apple.com/download/all](https://developer.apple.com/download/all/).
  Do **not** install an Xcode beta on a machine you ship from. If one is already
  installed, leave it out of `xcode-select`.
- **Xcode Command Line Tools** — `xcode-select --install`
- **Your Apple ID signed into Xcode** — Settings → Accounts. Needed so automatic
  signing can refresh provisioning profiles.
- **`git`**, and an SSH key registered with the GitHub account that can read the
  signing repo.
- **Python 3** — preinstalled on macOS.

Confirm the toolchain is *not* a beta:

```bash
xcode-select -p          # expect /Applications/Xcode.app/Contents/Developer
xcodebuild -version      # the version must not say "beta"
```

---

## 2. Secrets that git cannot carry

Three things are deliberately **not** in this repo and must arrive out of band
(password manager, AirDrop, encrypted USB — not email, not Slack):

| Secret | Where it goes | Notes |
|---|---|---|
| `AuthKey_24JDJGBV9T.p8` | `~/.asc/AuthKey_24JDJGBV9T.p8` | The App Store Connect API key. Apple lets you download it **once**; this copy is the only one. Account-scoped, shared with the Fajr app. |
| Signing repo password | `~/.asc/signing-sync-password` | Encrypts the signing repo contents. |
| `.p12` export password | needed once, during import | Protects the exported distribution identity. |

If the `.p8` is ever lost, revoke it in App Store Connect → Users and Access →
Integrations → App Store Connect API and issue a new one; then redo step 3 on
every machine.

---

## 3. Install and authenticate `asc`

```bash
curl -fsSL https://asccli.sh/install | bash
asc --version
```

The installer drops a prebuilt binary in `~/.local/bin`. If `asc` isn't found
afterwards, add that directory to your `PATH`.

```bash
mkdir -p ~/.asc && chmod 700 ~/.asc
# copy AuthKey_24JDJGBV9T.p8 into ~/.asc/ now, then:
chmod 600 ~/.asc/AuthKey_24JDJGBV9T.p8

asc auth login \
  --name "kessenma" \
  --key-id 24JDJGBV9T \
  --issuer-id 5e67a835-18f8-47a8-aa06-e1a43e9c5c44 \
  --private-key ~/.asc/AuthKey_24JDJGBV9T.p8 \
  --network

asc auth status --validate      # expect "validation":"works"
asc telemetry disable           # telemetry is on by default
```

Credentials land in the macOS keychain; `~/.asc/config.json` only records which
profile is the default.

---

## 4. Code signing

Archiving needs a distribution **certificate _and its private key_**. App Store
Connect will hand out the public certificate, but never the private key — so the
key has to come from a machine that already has it.

> **Do not create a new distribution certificate on each Mac.** The team is
> already at two `Apple Distribution` certs and Apple's ceiling is low. Burning a
> slot per machine is the problem shared signing exists to avoid.

Two ways to get it there. **Option B needs no setup and works today; Option A is
worth building only if you expect to onboard machines repeatedly.**

### Option A — pull from a signing repo

> **This repo does not exist yet.** `kessenma/die-kartei-signing` has to be
> created and seeded from a machine that already holds the private key before
> anything below will work. (The `die-kartei-certs` URL in
> `fastlane/.env.example` was never created either — ignore it.) Seed it with:
>
> ```bash
> asc signing sync push \
>   --bundle-id kyle-essenmacher.german-ai-flashcards \
>   --profile-type IOS_APP_STORE \
>   --repo git@github.com:kessenma/die-kartei-signing.git \
>   --password-file ~/.asc/signing-sync-password \
>   --identity ./distribution.p12 \
>   --identity-password-file ~/.asc/p12-password \
>   --create-missing
> ```
>
> Until then, use Option B.

Once the repo exists:

```bash
printf '%s' '<signing-repo-password>' > ~/.asc/signing-sync-password
chmod 600 ~/.asc/signing-sync-password

asc signing sync pull \
  --repo git@github.com:kessenma/die-kartei-signing.git \
  --password-file ~/.asc/signing-sync-password \
  --output-dir ./signing \
  --output json

security import ./signing/<identity>.p12 -k ~/Library/Keychains/login.keychain-db
asc profiles local install --path ./signing/<profile>.mobileprovision

rm -rf ./signing        # nothing here should linger; it's gitignored anyway
```

`asc profiles local install` picks the install directory by Xcode version
(Xcode 16+ → `~/Library/Developer/Xcode/UserData/Provisioning Profiles`, older →
`~/Library/MobileDevice/Provisioning Profiles`), which is why it's preferable to
copying the file by hand.

Several `asc signing sync` flags are marked experimental upstream. If it
misbehaves, use Option B — same end state.

### Option B — hand-carry the identity (works today)

On a Mac that already has the identity — the primary dev Mac does:

1. **Keychain Access** → **My Certificates** → select
   `Apple Distribution: Kyle Essenmacher (RHPLRY9X9P)` → right-click → **Export** →
   `.p12`, set a strong password.
2. Transfer the `.p12` out of band.

On the new Mac:

```bash
security import ~/Downloads/distribution.p12 -k ~/Library/Keychains/login.keychain-db
asc profiles download --app 6770390331 --output-dir ./signing
asc profiles local install --path ./signing/<profile>.mobileprovision
rm -rf ./signing ~/Downloads/distribution.p12
```

### How signing works — and two traps

`deploy.py` uses **automatic** signing and overrides nothing. That's a
deliberate choice forced by two facts, both verified the hard way:

**Trap 1 — the only App Store profile is Xcode-managed.** It's
`iOS Team Store Provisioning Profile: kyle-essenmacher.german-ai-flashcards`, and
an Xcode-managed profile *cannot* be combined with manual signing:

```
error: Provisioning profile "iOS Team Store Provisioning Profile: …" is Xcode
managed, but signing settings require a manually managed profile.
```

`asc profiles list` returns empty for this app, confirming there are no
manually-managed profiles in App Store Connect. Manual signing would require
creating one first — there's no reason to.

**Trap 2 — signing settings passed to `xcodebuild` apply to _every_ target.**
Putting `CODE_SIGN_IDENTITY=` / `PROVISIONING_PROFILE_SPECIFIER=` on the command
line leaks them into all the SPM package targets, which don't support profiles:

```
error: encuda does not support provisioning profiles …
error: swift-crypto_Crypto does not support provisioning profiles …
error: Bundle identifier is missing. CudaBuild doesn't have a bundle identifier …
```

The project's own `project.pbxproj` already sets `CODE_SIGN_STYLE = Automatic`
and `DEVELOPMENT_TEAM = RHPLRY9X9P`, so the correct move is to override nothing.

Because the Xcode GUI can't launch here, automatic signing is instead
authenticated with the App Store Connect API key, passed to the archive as
`-allowProvisioningUpdates -authenticationKeyPath/-KeyID/-KeyIssuerID`.

The archive is signed for *development* and re-signed for *distribution* at
export — that's normal. The resulting `.ipa` verifies as:

```
Authority=Apple Distribution: Kyle Essenmacher (RHPLRY9X9P)
profile: iOS Team Store Provisioning Profile: …   devices: NONE   get-task-allow: false
```

> **The profile expires 2026-11-29.** After that, archiving fails until Xcode
> regenerates it.

### Trap 3 — Xcode silently rewrites your build number

`manageAppVersionAndBuildNumber` in ExportOptions **defaults to YES**. With it
on, `xcodebuild -exportArchive` queries App Store Connect and bumps
`CFBundleVersion` on its own — observed here turning an archive containing build
3 into an `.ipa` containing build 4.

That defeats the whole point of computing a build number with
`asc builds next-build-number`, which is better informed than Xcode (it counts
in-flight uploads too). [`ExportOptions.plist`](../ExportOptions.plist) at the
repo root therefore sets it to `false`, and `deploy.py` passes that file
explicitly. **Don't delete that key** — without it the deploy reports one build
number and ships another.

### Confirm signing works

```bash
security find-identity -v -p codesigning | grep "Apple Distribution"
```

`deploy.py` checks this itself before archiving — along with the presence of
`ExportOptions.plist` and the API key — and aborts in seconds rather than after
a full build.

---

## 5. Pre-flight

```bash
git clone <this repo> && cd german-ai-flashcards

asc auth status --validate            # "validation":"works"
asc doctor                            # must exit 0
xcodebuild -version                   # must not say "beta"
security find-identity -v -p codesigning | grep "Apple Distribution"
asc builds list --app 6770390331 --sort -uploadedDate --limit 3 --output table
```

If all five are clean, you can ship.

---

## 6. Ship

```bash
# TestFlight
python3 scripts/deploy.py

# App Store — uploads and attaches the build, does NOT submit for review
python3 scripts/deploy.py release
```

### From VS Code

[`.vscode/tasks.json`](../.vscode/tasks.json) wires the same commands to the GUI —
no extra tooling, no `package.json`:

- **Cmd+Shift+B** runs *Deploy: TestFlight* (it's the default build task)
- **Cmd+Shift+P → "Tasks: Run Task"** lists all of them:
  *TestFlight*, *App Store (upload only)*, *Preflight checks*,
  *Clean build artifacts*, *Open latest log*

Build errors are parsed with the `$swiftc` problem matcher, so failures land in
the Problems panel and are clickable.

Release notes come from
[`german-ai-flashcards/Resources/whats_new.json`](../german-ai-flashcards/Resources/whats_new.json),
the same file the app renders under Settings ▸ About ▸ What's New. Add bullets to its
`unreleased` entry as features land (the procedure is in [`CLAUDE.md`](../CLAUDE.md));
the deploy script does the rest, see "What's New stamping" below. `CHANGELOG=…`
still overrides the TestFlight "What to Test" text for one run.

Both modes version themselves against App Store Connect before archiving:

- **Marketing version** is bumped until strictly greater than the highest live
  App Store version. Then, on a terminal, the script shows the recent uploads and
  asks:

  ```
  📜 Recent uploads: 1.4 (6, 5, 4); 1.3 (9)
  Continue building on version 1.4? [Y/n]:
  ```

  Enter keeps stacking builds on the current version. `n` asks for a new one
  (default: next minor, e.g. `1.5`), which must look like `x.y` or `x.y.z` and be
  above the live version. `VERSION=1.5 python3 scripts/deploy.py` answers without
  the prompt; with no terminal (CI) the current version is kept.
- **Build number** comes from `asc builds next-build-number`, which counts
  in-flight uploads as well as processed builds — safe even when a previous
  upload is still processing.

`release` deliberately stops short of submitting. Submit from App Store Connect
once you've reviewed the listing.

### What's New stamping

Once the marketing version is settled and before anything is archived, both modes
run `scripts/whats_new.py`'s `stamp` against
`german-ai-flashcards/Resources/whats_new.json`:

- The top `"version": "unreleased"` entry is renamed to the version being built and
  dated today. If an earlier TestFlight of the same version already claimed the
  entry, the new bullets are merged into it instead (duplicate titles skipped).
- Any versioned entry above the live App Store version that isn't the one being
  built never reached anyone (a TestFlight-only 1.5 when 1.6 is what ships) and is
  folded into the current one.
- The rendered entry (`• title — detail`, one per line) becomes the TestFlight
  "What to Test" text.
- `release` additionally refreshes the entry's date to today, **refuses to archive
  when the version has no entry**, and after the upload writes the same text into
  App Store Connect's What's New (en-US) with `asc localizations update`. That call
  is non-fatal: if the version is no longer editable the script prints the text for
  pasting.

The stamped file is a source change. **Commit it** after the deploy. A re-run with
nothing pending changes nothing, so an uncommitted stamp is harmless.

Rehearse the notes step without archiving:

```bash
VERSION=1.5 WHATS_NEW_ONLY=1 python3 scripts/deploy.py           # beta semantics
VERSION=1.5 WHATS_NEW_ONLY=1 python3 scripts/deploy.py release   # release semantics
git diff german-ai-flashcards/Resources/whats_new.json           # then keep or revert
```

Or drive the module directly on a copy:
`python3 scripts/whats_new.py stamp 1.5 --live 1.4 --dry-run --file /tmp/wn.json`.
`python3 scripts/whats_new.py check` validates the file; `render 1.4` prints what
shipped.

### The product page

Everything the App Store listing shows lives under `AppStore/`, one home and one script
per piece, and a `release` deploy pushes them all after the build lands and before
`asc validate`:

| What | Lives in | Script |
|---|---|---|
| Description, keywords, URLs, name | `AppStore/metadata/<locale>/` | `scripts/metadata.py` |
| Screenshots | `AppStore/screenshots/<locale>/<display type>/` | `scripts/screenshots.py` |
| What's New | `german-ai-flashcards/Resources/whats_new.json` | `scripts/whats_new.py` |

`AppStore/README.md` is the index. Each script also runs on its own with
`check` / `push --version X [--dry-run]` / `pull`, so any one piece can go up without
building anything.

```bash
python3 scripts/metadata.py check
python3 scripts/metadata.py push --version 1.6 --dry-run
python3 scripts/metadata.py pull --version 1.6      # rewrite the files from ASC
```

One file per field; an empty or missing file leaves that field alone rather than
clearing it. `description.md` is pushed verbatim — the App Store renders no Markdown,
so `check` warns when Markdown syntax appears in it. `SKIP_METADATA=1` skips the push
for one run.

**What's New is deliberately not in `AppStore/metadata/`.** The app ships the same text
(Settings ▸ About ▸ What's New), so the file has to live in the app bundle;
`AppStore/whats_new.json` is a symlink to it. `scripts/metadata.py` has no
`--whats-new` flag on purpose — one field with two writers is one field that drifts.

### Screenshots

App Store screenshots live in `AppStore/screenshots/<locale>/<display type>/`, one
folder per App Store display type, and are pushed by `scripts/screenshots.py`. A
`release` deploy uploads them after the build lands and before `asc validate`, so
the readiness report sees them. TestFlight has no screenshots, so `beta` runs never
touch them.

```bash
python3 scripts/screenshots.py check                       # sizes and order, locally
python3 scripts/screenshots.py push --version 1.6 --dry-run
python3 scripts/screenshots.py push --version 1.6
python3 scripts/screenshots.py pull --version 1.5          # what the store shows now
```

Uploads are additive and matched by MD5 (`--skip-existing`), so a re-run is free and
an unchanged image is never re-sent. Nothing is ever deleted: a file removed from
the folder stays on the product page until it is removed in App Store Connect.
An empty set folder is skipped, so an unfinished iPad set never blocks a release.
`SKIP_SCREENSHOTS=1` leaves the product page alone for one run.

The version has to exist in App Store Connect before a push, and a `release` deploy
is what creates it — so the first push for a new version happens inside that deploy.
`AppStore/screenshots/README.md` has the sizes and the export routine.

### Dry run — prove the build works without shipping anything

Useful when you want to confirm the toolchain, certificate, and profile are all
good but aren't ready to release: this produces a signed `.ipa` locally and sends
**nothing** to Apple. No version bump, no upload, nothing that can't be undone by
deleting a file.

```bash
# 1. Archive (signed, but purely local). Overrides no signing settings —
#    see "two traps" above for why that matters.
asc xcode archive \
  --project german-ai-flashcards.xcodeproj \
  --scheme german-ai-flashcards \
  --configuration Release \
  --archive-path .asc/artifacts/DieKartei.xcarchive \
  --clean --overwrite \
  --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS \
  --xcodebuild-flag=-allowProvisioningUpdates \
  --xcodebuild-flag=-authenticationKeyPath --xcodebuild-flag=$HOME/.asc/AuthKey_24JDJGBV9T.p8 \
  --xcodebuild-flag=-authenticationKeyID --xcodebuild-flag=24JDJGBV9T \
  --xcodebuild-flag=-authenticationKeyIssuerID --xcodebuild-flag=5e67a835-18f8-47a8-aa06-e1a43e9c5c44 \
  --output json --pretty

# 2. Export a signed .ipa using the repo's ExportOptions.plist
asc xcode export \
  --archive-path .asc/artifacts/DieKartei.xcarchive \
  --ipa-path .asc/artifacts/DieKartei.ipa \
  --export-options ExportOptions.plist \
  --overwrite --output json --pretty
```

`--export-options` is mutually exclusive with `--signing-style` / `--team-id`;
those values live inside the plist instead.

If both succeed you have a shippable binary at `.asc/artifacts/DieKartei.ipa`
(gitignored). A real deploy adds only the version bump and the upload on top.
Reference timing on this project: ~7 minutes for a clean archive plus export.

Verify what you actually built:

```bash
cd $(mktemp -d) && unzip -q /path/to/DieKartei.ipa && APP=$(ls -d Payload/*.app)
codesign -dv --verbose=2 "$APP" 2>&1 | grep Authority   # expect Apple Distribution
plutil -extract CFBundleVersion raw "$APP/Info.plist"    # must match your archive
```

Optionally validate the binary against Apple before ever uploading:

```bash
asc xcode validate --ipa .asc/artifacts/DieKartei.ipa \
  --api-key 24JDJGBV9T \
  --api-issuer 5e67a835-18f8-47a8-aa06-e1a43e9c5c44 \
  --output json
```

> `asc xcode validate` shells out to `xcrun altool`, which finds the private key
> only in its own fixed search paths — **not** `~/.asc/`. Make it visible once:
> ```bash
> mkdir -p ~/.appstoreconnect/private_keys
> ln -s ~/.asc/AuthKey_24JDJGBV9T.p8 ~/.appstoreconnect/private_keys/AuthKey_24JDJGBV9T.p8
> ```
> Everything else in this doc reads the key from `~/.asc/` and needs no such link.

Clean up with `rm -rf .asc/artifacts` when you're done.

### Environment overrides

| Variable | Default | Effect |
|---|---|---|
| `VERSION` | — | Marketing version to ship as, e.g. `1.5`; skips the version prompt. Must be above the live App Store version |
| `BUMP` | `minor` | Marketing-version step used by the version-ahead guard: `patch`, `minor`, `major` |
| `CHANGELOG` | — | Overrides the TestFlight notes rendered from `whats_new.json` for one run |
| `WHATS_NEW_ONLY` | — | `1` stops right after `whats_new.json` is stamped: no archive, no upload |
| `SKIP_METADATA` | — | `1` skips the description/keywords push (`release` only) |
| `SKIP_SCREENSHOTS` | — | `1` skips the App Store screenshot upload (`release` only) |
| `TESTFLIGHT_GROUP` | `internal-die-Kartei` | Target beta group (name or ID) |
| `NOTIFY_TESTERS` | — | `true` notifies testers after distribution |
| `XCODE_PATH` | — | Pin a toolchain for one run, e.g. `/Applications/Xcode.app` |
| `ASC_KEY_PATH` | `~/.asc/AuthKey_24JDJGBV9T.p8` | Location of the API key used for signing auth |

Logs are written to `build-logs/deploy-{beta,release}/YYYY-MM-DD/`, 10 kept per
mode.

---

## Troubleshooting

**`asc: command not found`** — the installer writes to `~/.local/bin`. Add it to
`PATH`, or re-run the install with `INSTALL_DIR=/usr/local/bin`.

**The Xcode app won't launch** (`_LSOpenURLsWithCompletionHandler() failed …
error -10664`). A newer macOS can refuse to launch an older Xcode's GUI — on this
setup, macOS 27 beta blocks Xcode 26.5. **This does not block deploying.** The
command-line toolchain in the same bundle still works; confirm with:

```bash
xcodebuild -version
xcodebuild -project german-ai-flashcards.xcodeproj -list   # real work, not just a version print
```

If both succeed you can ship. What you lose is the GUI, which means you cannot
add or refresh an Apple ID signing account — hence the manual, pinned signing in
section 4, which needs no account at all.

**Several identical `Apple Distribution: Kyle Essenmacher (RHPLRY9X9P)` identities.**
Certificates issued under the same team share a common name, so selecting one
*by name* is ambiguous. Automatic signing resolves this itself, which is one more
reason not to override it. If you ever need to know which cert a profile actually
trusts, decrypt it and compare embedded certificates against the keychain:

```bash
security cms -D -i "<uuid>.mobileprovision" > /tmp/p.plist
plutil -extract DeveloperCertificates.0 raw -o - /tmp/p.plist | base64 -d \
  | openssl x509 -inform DER -noout -subject -enddate -fingerprint -sha1
security find-identity -v -p codesigning
```

The right cert is one that appears in **both** lists. When a profile embeds
several, prefer the one whose expiry matches the profile's own.

**`Repository not found` on the signing repo.** The SSH key on this Mac isn't
registered with a GitHub account that can read it. Check with
`ssh -T git@github.com` — it should greet you by username.

**Deploy aborts with "A BETA Xcode is selected".** Working as intended. Either
`sudo xcode-select -s /Applications/Xcode.app`, or pin for a single run with
`XCODE_PATH=/Applications/Xcode.app python3 scripts/deploy.py`.

**ITMS-90111 "Unsupported SDK or Xcode version" even though `xcodebuild -version`
is a release.** ASC also keys this rejection off `BuildMachineOSBuild` in the
app's Info.plist, which Xcode stamps with the *host* macOS build. A beta host
(build ending in a lowercase letter, e.g. `26A5421a`) trips it even with a
release Xcode and SDK. Fixed on 2026-09-07 by the "Stamp release macOS build"
phase on the Die Kartei target, which rewrites that key (in the app and the SPM
resource bundles) to the macOS build of the selected Xcode's own macOS SDK,
before code signing. If it comes back, check that the phase is still the
target's **last** build phase and that `ENABLE_USER_SCRIPT_SANDBOXING` is `NO`
for the target (a sandboxed script cannot touch the built Info.plist). Every
deploy log ends with a stamp line read from the exported IPA; `✅ … all release
builds` is what you want.

The phase acts on **archives only** (`ACTION=install`). Debug, simulator and
test builds, including ones made in Xcode-beta for day-to-day work, get a
one-line note and are otherwise untouched. Archiving *with* a beta Xcode is
refused outright, since ASC checks `DTXcodeBuild` too and no stamp would save
it. Note that the seed-suffix rule does not hold for SDK builds: the release
Xcode 26.6 ships iOS SDK `23F81a`, which ASC accepts. To inspect any build by
hand:

```bash
unzip -p .asc/artifacts/<name>.ipa 'Payload/*.app/Info.plist' > /tmp/i.plist
plutil -p /tmp/i.plist | grep -E 'DTXcodeBuild|DTSDKBuild|BuildMachineOSBuild'
```

**Deploy aborts with "… build phase is missing".** Restore the phase: in the
pbxproj it is the `PBXShellScriptBuildPhase` named "Stamp release macOS build"
running `/bin/bash "${SRCROOT}/scripts/stamp-release-os.sh"`, listed last in
the target's `buildPhases`. Or archive on a release macOS, where the phase is a
no-op anyway.

**"BUMP=patch cannot overtake the live version".** A patch bump can never pass a
higher *minor* — e.g. `1.2.x` will never exceed a live `1.3`. Re-run with
`BUMP=minor` or `BUMP=major`.

**`There is no resource of type 'apps' with id 'kyle-essenmacher...'`.** Some
`asc` subcommands (`versions`, `testflight`) require the **numeric** app ID
`6770390331` rather than the bundle ID, even though `builds` accepts either.

**Build uploaded but never appears.** Processing can lag. Check state directly:
`asc builds list --app 6770390331 --sort -uploadedDate --limit 5 --output table`.
That list only holds uploads that *became* builds. One that was rejected on
delivery is in `asc builds uploads list --app 6770390331`, with Apple's error
codes attached.

**ITMS-90186 "the train version 'x.y' is closed for new build submissions",
usually alongside ITMS-90062 "must contain a higher version than that of the
previously approved version".** That marketing version is burned: App Store
Connect will reject every future upload carrying it, and nothing in
`asc versions list` says so — the version record can still read
`PREPARE_FOR_SUBMISSION` while the train behind it is shut. It happens when a
version has been approved by App Review, or when its version record was deleted
after the fact. The only cure is a higher `CFBundleShortVersionString`.

Since 2026-09-16 the deploy script reads past rejections from
`asc builds uploads list` and bumps the marketing version past every burned one
before archiving, so a plain re-run recovers on its own; `VERSION=1.6` still
overrides. First hit: 1.5 closed while the App Store was live on 1.4, wasting
two full archive-and-upload runs (2026-09-15 and 2026-09-16). A burned version
also leaves a stale, buildless version record in App Store Connect — delete it
by hand (`asc versions delete`, only possible in `PREPARE_FOR_SUBMISSION`) so
the app's version list doesn't grow phantom entries.

Its What's New bullets are not lost: `whats_new.stamp` folds any entry above the
live App Store version into the version actually shipping, so 1.5's highlights
move to 1.6 on the next deploy.

---

## Relationship to fastlane

The `fastlane/` directory is retained as a rollback path and for its metadata
files. **It is not used by `scripts/deploy.py` and is not currently
functional** — `fastlane/.env` and the `.p8` it expects are absent, and the match
repo referenced in `fastlane/.env.example` (`die-kartei-certs`) was never created.
Don't try to run `bundle exec fastlane` here without setting all of that up first.

The React Native apps in other repos still use fastlane normally; nothing here
affects them.
