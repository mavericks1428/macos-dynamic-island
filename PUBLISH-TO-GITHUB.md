# How to publish AirIsland to your GitHub account

Written for someone who has a GitHub account but hasn't done this before. Pick **one** of the three routes — Route 1 needs no tools at all.

> **Already set up for you.** Every placeholder now contains **`mavericks1428`**: the README build badge and clone URL, the `LICENSE` copyright line, and the `User-Agent` the app sends to LRCLIB. I checked your account and you have no public repos yet, so `macos-dynamic-island` is free to claim — you can start at Route 1 straight away.
>
> If you ever rename the repo or move it to an organisation, update those four spots. As a one-liner from inside the folder:
>
> ```bash
> grep -rl "mavericks1428/macos-dynamic-island" . --exclude-dir=.git \
>   | xargs sed -i '' "s|mavericks1428/macos-dynamic-island|NEW-OWNER/NEW-NAME|g"
> ```

---

## Route 1 — Web only (easiest, no Terminal)

1. Go to **https://github.com/new**.
2. **Repository name:** `macos-dynamic-island` *(exactly this — the README badge and clone URL already point at it)*
3. **Description:** `A native Dynamic Island for macOS 12 — pure SwiftUI + AppKit, no dependencies.`
4. Select **Public**. Do **not** tick "Add a README" (you already have one — it would conflict).
5. Click **Create repository**.
6. On the empty repo page, click **uploading an existing file**.
7. **Drag the entire contents** of the `AirIsland` folder into the page — the `.swift` files, `AppResources/`, `Sources/`, `README.md`, `LICENSE`, `build.sh`, the two `.command` files, `SECURITY.md`, `.gitignore`, `.github/`.
   - **Important:** drag the *files inside*, not the outer folder, so the repo root looks like `Sources/…` and not `AirIsland/Sources/…`.
   - Hidden files (`.gitignore`, `.github/`) often won't drag from Finder. Fix them afterwards: **Add file → Create new file**, name it `.gitignore`, paste the contents. Repeat for `.github/workflows/build.yml`.
8. Click **Commit changes**.
9. Your repo is live at `https://github.com/mavericks1428/macos-dynamic-island`.
10. Go to the **Actions** tab, click **I understand my workflows, go ahead and enable them** if prompted. The first build proves it compiles on a real macOS runner.

---

## Route 2 — GitHub Desktop (recommended if you'll update it)

1. Install **GitHub Desktop** from https://desktop.github.com and sign in.
2. **File → Add local repository** → choose your `Downloads/AirIsland` folder.
3. It will say "this directory is not a Git repository" — click **create a repository**.
4. Name: `macos-dynamic-island`, description as above, **Git ignore: None**, **License: None** (you already have both files).
5. Click **Create repository**. This commits the files locally — nothing is on GitHub yet.
6. In the top bar click **Publish repository**:
   - **Uncheck "Keep this code private"** so it becomes public.
   - Click **Publish repository**. Done — it's live at `https://github.com/mavericks1428/macos-dynamic-island`.
7. For future updates: edit files → type a **Summary** → **Commit to main** → **Push origin**.

---

## Route 3 — Terminal (git commands)

```bash
cd ~/Downloads/AirIsland          # the folder containing README.md, Sources/, etc.

# Optional but nice: make sure the scripts stay executable in the repo
chmod +x build.sh "Install AirIsland.command" "Fix Gatekeeper.command"

# Option A — GitHub CLI handles login + repo creation + push in one go
#   (install once with: brew install gh)
gh auth login
gh repo create macos-dynamic-island --public --source=. --remote=origin --push

# Option B — create the empty repo at https://github.com/new first, then:
git init
git add .
git commit -m "AirIsland 1.0.0 — native Dynamic Island for macOS 12"
git branch -M main
git remote add origin https://github.com/mavericks1428/macos-dynamic-island.git
git push -u origin main
```

*(The workspace copy I prepared already has two commits and correct file modes, so `git init`/`git add`/`git commit` are only needed if you start from the plain zip — if you use `gh repo create` on this exact folder, it pushes straight away.)*

The first `git push` asks for credentials. On GitHub, **your account password no longer works** — use either:

- **A Personal Access Token:** GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → *Generate new token* → tick **repo** → copy it → paste it as the password.
- **SSH instead:** `ssh-keygen -t ed25519 -C "you@example.com"` then add `~/.ssh/id_ed25519.pub` under GitHub → Settings → SSH and GPG keys, and use the `git@github.com:...` remote URL.
- **Or** let the browser pop-up handle it: install **Git Credential Manager** (`brew install --cask git-credential-manager`) and `git push` opens a login window.

---

## After it's published

### Make the repo look finished
On the repo page, click the gear next to **About** (top right) and fill in:

- **Description:** `A native Dynamic Island for macOS 12 — pure SwiftUI + AppKit, no dependencies.`
- **Website:** leave blank
- **Topics:** `macos`, `swiftui`, `appkit`, `dynamic-island`, `macos-app`, `menu-bar`, `spotify`, `now-playing`, `monterey`, `swift`

### Confirm the build badge works
`README.md` already contains a badge pointing at `mavericks1428/macos-dynamic-island`. After your first Actions run it turns green (or red — click it to see why). If you never enabled Actions, the badge shows "no status", which is harmless.

### Make a release (so people can download the app, not just the source)
1. On your Mac, build it: `./build.sh dmg` → produces `AirIsland-1.0.0.dmg`.
2. GitHub repo → **Releases** → **Draft a new release**.
3. Tag: `v1.0.0` → click "Create new tag: v1.0.0 on publish".
4. Title: `AirIsland 1.0.0`.
5. Drag `AirIsland-1.0.0.dmg` into the **Attach binaries** box.
6. Describe what it does, then **Publish release**.

Downloaders will still hit the Gatekeeper prompt (no paid Apple Developer certificate), so keep the "unidentified developer" note in the release text and point them at `SECURITY.md`.

### Things worth knowing
- **Don't commit build output.** `.gitignore` already excludes `.build/`, `*.app`, `*.dmg`.
- **Never commit secrets.** There are none today — keep it that way.
- **GitHub Actions on a public repo is free**, including on `macos-12` runners. macOS minutes cost 10× Linux minutes, so a public repo is the only reason this stays comfortably within the free tier.
- **Forking/licensing:** with MIT, anyone can reuse it as long as they keep your copyright line in `LICENSE`.
- **Naming.** "AirIsland" and "Dynamic Island" are Apple marketing terms. Apple's trademark guidelines discourage implying your app is an Apple product — hence the repo name `macos-dynamic-island` and the "not affiliated with Apple" line you may want to add to the README footer. Many community apps do this; a short disclaimer is the safe move:

  > *Not affiliated with, endorsed by, or sponsored by Apple Inc. “Dynamic Island” is a trademark of Apple Inc.*

### If you'd rather I did it for you
Connect GitHub in this chat (Settings → Connectors) and I can create the repo, commit these files and open the release directly — no Terminal needed on your side.
