# Deploy setup — getting a new Mac from zero to shipping

Die Kartei deploys through the [App Store Connect CLI](https://github.com/rorkai/App-Store-Connect-CLI)
(`asc`), driven by [`scripts/deploy.py`](../scripts/deploy.py).

Follow this top to bottom on a machine that has never deployed this app. Budget
~20 minutes, most of it Xcode downloading.

> **What matters is the Xcode/SDK that builds the binary, not the host macOS and
> not the Xcode GUI.** App Store Connect accepts binaries built with a beta Xcode
> on *upload* and rejects them at *submission* ("Unsupported SDK or Xcode
> version"). `deploy.py` aborts before archiving if it detects a beta toolchain.
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
security find-identity -v -p codesigning | grep F7140E42E2581B6280A45649513A244FCAF480D7
                              # a match -> section 4 done
xcodebuild -version           # must not say "beta"
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

### How signing is pinned

`deploy.py` signs **manually**, pinning both the certificate and the profile, so
the result can't drift with whatever Xcode happens to prefer:

| | |
|---|---|
| Identity (SHA-1) | `F7140E42E2581B6280A45649513A244FCAF480D7` |
| Profile | `iOS Team Store Provisioning Profile: kyle-essenmacher.german-ai-flashcards` |

Manual signing is deliberate. Several distribution certs share the common name
`Apple Distribution: Kyle Essenmacher (RHPLRY9X9P)`, so selecting by *name* is
ambiguous — that SHA-1 is the one the App Store profile above was minted for
(their expiry timestamps match exactly). It also means signing needs nothing from
the Xcode GUI or a signed-in Apple ID.

> **The profile expires 2026-11-29.** After that, archiving fails until it's
> regenerated. `asc profiles list --output table` shows what App Store Connect
> has; a profile that only exists locally (Xcode-managed) won't appear there.

Override per run if the identity or profile ever changes:

```bash
SIGNING_IDENTITY=<sha1> PROVISIONING_PROFILE="<name>" python3 scripts/deploy.py
SIGNING_STYLE=automatic python3 scripts/deploy.py   # let Xcode resolve it instead
```

### Confirm signing works

```bash
security find-identity -v -p codesigning | grep F7140E42E2581B6280A45649513A244FCAF480D7
```

`deploy.py` runs this check itself before archiving and aborts with a clear
message if the identity is missing — so you find out in seconds rather than
after a full build.

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

Edit [`fastlane/changelog.txt`](../fastlane/changelog.txt) beforehand so the
TestFlight "What to Test" notes are picked up without prompting. (That file still
lives under `fastlane/` for historical reasons; the deploy script no longer uses
fastlane itself.)

Both modes version themselves against App Store Connect before archiving:

- **Marketing version** is bumped until strictly greater than the highest live
  App Store version.
- **Build number** comes from `asc builds next-build-number`, which counts
  in-flight uploads as well as processed builds — safe even when a previous
  upload is still processing.

`release` deliberately stops short of submitting. Submit from App Store Connect
once you've reviewed the listing.

### Dry run — prove the build works without shipping anything

Useful when you want to confirm the toolchain, certificate, and profile are all
good but aren't ready to release: this produces a signed `.ipa` locally and sends
**nothing** to Apple. No version bump, no upload, nothing that can't be undone by
deleting a file.

```bash
# 1. Archive (signed, but purely local)
asc xcode archive \
  --project german-ai-flashcards.xcodeproj \
  --scheme german-ai-flashcards \
  --configuration Release \
  --archive-path .asc/artifacts/DieKartei.xcarchive \
  --clean --overwrite \
  --xcodebuild-flag=-destination --xcodebuild-flag=generic/platform=iOS \
  --xcodebuild-flag=CODE_SIGN_STYLE=Manual \
  --xcodebuild-flag=CODE_SIGN_IDENTITY=F7140E42E2581B6280A45649513A244FCAF480D7 \
  "--xcodebuild-flag=PROVISIONING_PROFILE_SPECIFIER=iOS Team Store Provisioning Profile: kyle-essenmacher.german-ai-flashcards" \
  --output json --pretty

# 2. Export a signed .ipa
asc xcode export \
  --archive-path .asc/artifacts/DieKartei.xcarchive \
  --ipa-path .asc/artifacts/DieKartei.ipa \
  --signing-style manual --team-id RHPLRY9X9P \
  --overwrite --output json --pretty
```

Note the quoting on the profile flag — the profile name contains spaces, so the
whole `--xcodebuild-flag=…` token must be quoted as one argument.

If both succeed you have a shippable binary at `.asc/artifacts/DieKartei.ipa`
(gitignored). A real deploy adds only the version bump and the upload on top.

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
| `BUMP` | `minor` | Marketing-version step: `patch`, `minor`, `major` |
| `CHANGELOG` | — | Overrides `fastlane/changelog.txt` for one run |
| `TESTFLIGHT_GROUP` | `internal-die-Kartei` | Target beta group (name or ID) |
| `NOTIFY_TESTERS` | — | `true` notifies testers after distribution |
| `XCODE_PATH` | — | Pin a toolchain for one run, e.g. `/Applications/Xcode.app` |
| `SIGNING_STYLE` | `manual` | `automatic` lets Xcode resolve signing instead |
| `SIGNING_IDENTITY` | pinned SHA-1 | Override the signing certificate |
| `PROVISIONING_PROFILE` | pinned name | Override the provisioning profile |

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
*by name* is ambiguous and Xcode may pick the wrong one. That's why signing is
pinned by SHA-1. To work out which cert a profile actually trusts, decrypt it and
compare embedded certificates against the keychain:

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

**"BUMP=patch cannot overtake the live version".** A patch bump can never pass a
higher *minor* — e.g. `1.2.x` will never exceed a live `1.3`. Re-run with
`BUMP=minor` or `BUMP=major`.

**`There is no resource of type 'apps' with id 'kyle-essenmacher...'`.** Some
`asc` subcommands (`versions`, `testflight`) require the **numeric** app ID
`6770390331` rather than the bundle ID, even though `builds` accepts either.

**Build uploaded but never appears.** Processing can lag. Check state directly:
`asc builds list --app 6770390331 --sort -uploadedDate --limit 5 --output table`.

---

## Relationship to fastlane

The `fastlane/` directory is retained as a rollback path and for its metadata and
changelog files. **It is not used by `scripts/deploy.py` and is not currently
functional** — `fastlane/.env` and the `.p8` it expects are absent, and the match
repo referenced in `fastlane/.env.example` (`die-kartei-certs`) was never created.
Don't try to run `bundle exec fastlane` here without setting all of that up first.

The React Native apps in other repos still use fastlane normally; nothing here
affects them.
