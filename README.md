# macOS Bootstrap

A single script that takes a fresh Mac from factory state to a fully configured development environment. Declarative, reproducible, and idempotent.

## What it does

The bootstrap script automates the following in order:

1. Installs Xcode Command Line Tools (provides `git`, `clang`, etc.)
2. Installs Homebrew (with bulletproof PATH setup + temporary `.zprofile` bridge for persistence between runs)
3. Installs bootstrap dependencies (`gh` and `chezmoi` via Homebrew)
4. Authenticates with GitHub (browser-based OAuth — no SSH key needed)
5. Clones dotfiles repo via chezmoi (HTTPS, credential helper already configured)
6. Applies dotfiles (places Brewfile, zshrc, mise config, starship config, etc.)
7. Installs all packages from Brewfile (CLI tools, casks, fonts, App Store apps)
8. Re-evaluates chezmoi templates (so .gitconfig detects delta, gh, difft, etc.)
9. Removes pre-installed bloatware (GarageBand, iMovie, Keynote, Numbers, Pages + sound libraries)
10. Disables redundant built-in apps (clears Dock, prints Screen Time guide)
11. Installs Oh-My-Zsh (framework for zsh plugins and completions)
12. Sets Homebrew zsh as the default shell (with ZDOTDIR → `~/.config/zsh/`)
13. Cleans up legacy zsh files (`~/.zprofile`, `~/.zshrc`, `~/.zcompdump*`, etc. — superseded by ZDOTDIR config)
14. Configures macOS system defaults (Finder, Dock, keyboard, trackpad, screenshots, security)
15. Sets 24-hour time system-wide (menu bar, lock screen)
16. Configures power management (battery: 3m display/10m sleep; charger: 15m display/never sleep)
17. Creates PARA directory structure (`0-inbox` through `4-archive` + Developer workspace)
18. Installs LazyVim starter and overlays Neovim customizations from dotfiles
19. Installs language runtimes via mise (`~/.config/mise/config.toml`: Node, Python, Go, Rust)
20. Installs Rust components (rustfmt, clippy, rust-analyzer)
21. Generates static zsh completion files (gh, chezmoi, just, uv, rustup, cargo, starship, atuin, docker)
22. Verifies all shell tools are present

## Prerequisites

A Mac and a GitHub account. That's it. Everything else is installed by the script.

The script handles GitHub authentication automatically — it installs the GitHub CLI, walks you through browser-based login, and configures git's HTTPS credential helper before attempting to clone your dotfiles. No SSH keys, personal access tokens, or manual setup required. SSH keys are optionally used later for commit signing (not transport).

## Full setup walkthrough

### Step 1: Complete macOS Setup Assistant

Power on your new Mac and go through Apple's initial setup:

- Select language, region, and Wi-Fi
- Sign in with your Apple ID (or create one)
- Enable FileVault when prompted (full-disk encryption — critical for security)
- Skip iCloud Keychain migration for now (your password manager handles credentials)

### Step 2: Sign in to the Mac App Store

This must happen **before** running the bootstrap script if your Brewfile contains `mas` entries (App Store apps like Xcode, Amphetamine, etc.).

1. Open **App Store** from the Dock or Spotlight (`Cmd + Space`, type "App Store")
2. Click your profile icon in the bottom-left corner
3. Sign in with your Apple ID
4. Verify you're signed in (your name should appear)

The script will pause and remind you if it detects `mas` entries and you aren't signed in, but it's easier to do this upfront.

### Step 3: Run the bootstrap script

Open **Terminal** (Spotlight → "Terminal") and run:

```bash
# Option A: One-liner (download and run)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/joshroy01/bootstrap/main/bootstrap.sh)"
```

```bash
# Option B: Download the repo first (inspect before running)
curl -fsSL https://github.com/joshroy01/bootstrap/archive/main.tar.gz | tar xz
cd bootstrap-main
less bootstrap.sh          # review it
bash bootstrap.sh          # run it
```

> **Note:** Option B uses GitHub's tarball endpoint — no `git` required (it isn't available until Xcode CLI tools install).

**What to expect:**

- **Xcode CLI tools** — a system dialog will appear. Click "Install" and wait (2–5 minutes).
- **Homebrew** — prompts for your password once (needs `sudo` to create `/opt/homebrew`). A temporary `~/.zprofile` is written so `brew` persists on PATH if the script is interrupted and re-run from a new terminal. This file is cleaned up later in the process.
- **GitHub authentication** — the script installs `gh`, then opens your browser for OAuth login. You'll see a one-time code in the terminal — enter it in the browser to authorize. This takes about 30 seconds. Once authenticated, the script configures git to use `gh` as a credential helper, so all git operations over HTTPS (including chezmoi's dotfiles clone, pushes, and pulls) work automatically. No SSH keys or personal access tokens needed.
- **Chezmoi prompts** — you'll be asked for your name, email, GitHub username, preferred editor, and SSH signing key (press Enter to skip on first run). These values are stored in `~/.config/chezmoi/chezmoi.toml` and used to template your dotfiles.
- **Brewfile** — first run takes 10–30 minutes depending on your connection. Cask installs may trigger macOS security prompts.
- **Template re-evaluation** — after the Brewfile installs all tools, chezmoi re-renders templates so your `.gitconfig` picks up delta, gh, difft, and your `.chezmoi.toml` detects cursor/nvim.
- **Oh-My-Zsh** — installed with `KEEP_ZSHRC=yes` so it doesn't overwrite your chezmoi-managed `.zshrc`.
- **Default shell change** — prompts for your password once (`chsh` requires it).
- **Legacy zsh cleanup** — removes `~/.zprofile` (Homebrew bridge), `~/.zshrc`, `~/.zcompdump*`, and other zsh files from `$HOME` that are superseded by your ZDOTDIR config in `~/.config/zsh/`.
- **Bloatware removal** — deletes GarageBand, iMovie, Keynote, Numbers, Pages and their sound libraries. These may return after major macOS updates; re-run to clean up.
- **Dock rebuild** — the Dock is cleared entirely (no pinned apps). Launch apps via Raycast (`Cmd + Space`) instead.
- **Neovim plugins** — headless install runs silently. If it has issues, plugins finish installing on first launch.

The script is **idempotent** — you can re-run it safely. It skips steps that are already complete (authenticated, installed, cloned, etc.).

### Step 4: Restart your terminal

Close Terminal entirely and open your terminal emulator (WezTerm or Ghostty, now installed by the Brewfile):

```bash
# Or from the existing terminal:
exec zsh
```

Your shell should now have Starship prompt, syntax highlighting (Cosmic Storm theme), autosuggestions, and all tool integrations (atuin, zoxide, direnv, fzf, mise) active.

### Step 5: Grant app permissions

Several apps need macOS security permissions to function. Each app will prompt you on first launch, but here's the complete list so nothing gets missed. All permissions are granted in **System Settings → Privacy & Security**.

| App | Permission(s) | Path in System Settings |
|-----|--------------|------------------------|
| **Your terminal** (WezTerm, Ghostty, iTerm2) | Full Disk Access | Privacy & Security → Full Disk Access |
| **AeroSpace** | Accessibility | Privacy & Security → Accessibility |
| **Karabiner-Elements** | Accessibility, Input Monitoring | Privacy & Security → Accessibility *and* Input Monitoring |
| **Raycast** | Accessibility | Privacy & Security → Accessibility |
| **LuLu** | Network Extension | Privacy & Security → Network Extensions (requires restart) |
| **Pearcleaner** | Full Disk Access, Accessibility | Privacy & Security → Full Disk Access *and* Accessibility |

> **Why Full Disk Access for the terminal?** Without it, tools like `du`, `rsync`, `find`, and backup scripts can't access macOS-protected directories (sandboxed app containers, Mail, Messages, etc.). You'll see "Operation not permitted" errors.

### Step 6: Configure apps that need manual setup

A few things can't be fully automated:

**Raycast — replace Spotlight:**
1. Open **System Settings → Keyboard → Keyboard Shortcuts → Spotlight**
2. Uncheck "Show Spotlight search" (frees up `Cmd + Space`)
3. Open Raycast, go to **Settings → General**, and set the Raycast Hotkey to `Cmd + Space`
4. Enable "Launch at Login" in Raycast settings

> **Note:** Raycast uses the Spotlight index for file search — don't disable Spotlight entirely, just its keyboard shortcut.

**Notification sounds:**

The bootstrap disables Messages send/receive sounds via `defaults write`. To silence notification sounds for other apps while keeping banners visible:

1. Open **System Settings → Notifications**
2. Select each app (Messages, Mail, Slack, Discord, Calendar, etc.)
3. Toggle off **"Play sound for notifications"**

This can't be automated — macOS stores per-app notification preferences in a protected database.


**Atuin — shell history sync:**
```bash
atuin register   # create new account for cross-machine sync
# OR
atuin login      # log into existing account
# OR skip both to use atuin in offline-only mode
```

Atuin owns `Ctrl-R` (history search). fzf handles `Ctrl-T` (file search) and `Alt-C` (directory jump).

**Bitwarden — password manager + commit signing:**

1. Open the Bitwarden desktop app and sign in to your vault
2. Sign in to the browser extension as well

**Set up SSH commit signing (recommended):**

The bootstrap uses HTTPS for all git transport (clone, push, pull) via the `gh` credential helper — no SSH keys needed for basic operations. SSH keys are used for *commit signing* to get verified badges on your commits.

```bash
# Step 1: Enable Bitwarden SSH agent
# Bitwarden desktop → Settings → SSH Agent → Enable
# This creates ~/.bitwarden-ssh-agent.sock
# Your shell already points SSH_AUTH_SOCK at this socket (exports/main.zsh)

# Step 2: Generate a signing key in Bitwarden
# Bitwarden desktop → New → SSH key → Ed25519
# Name it clearly: "Personal Signing Key (Ed25519)"
# Copy the public key (ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...)

# Step 3: Upload to GitHub (add it TWICE — once for each purpose)
# GitHub → Settings → SSH and GPG keys → New SSH key
#   - Type: Authentication Key  → paste public key
#   - Type: Signing Key         → paste public key

# Step 4: Enable signing in your dotfiles
chezmoi init --force
# When prompted for "SSH signing key", paste your public key
chezmoi apply

# Step 5: Verify
ssh-add -l                                        # should list your key
git commit --allow-empty -m "test signing"        # should succeed
git log --show-signature -1                        # should show "Good signature"
```

If you use separate GitHub accounts for work and personal, generate a separate key for each in Bitwarden (e.g., "Work Signing Key (Ed25519)"). During `chezmoi init` on each machine, paste the appropriate public key — the `machine_type` variable already supports per-machine differentiation.

**On a new machine**, this is the flow after the bootstrap completes:
1. Sign in to Bitwarden desktop → enable SSH agent
2. Your keys are already in the vault, synced from the cloud
3. Run `chezmoi init --force`, paste the same public key when prompted
4. Done — the private key never exists as a file on disk

**Karabiner-Elements:**
- Launch it and approve both the Accessibility and Input Monitoring permission prompts
- Your config at `~/.config/karabiner/karabiner.json` (managed by chezmoi) is picked up automatically

**AeroSpace:**
- Launch it once and approve the Accessibility permission prompt
- The TOML config at `~/.config/aerospace/aerospace.toml` (managed by chezmoi) is picked up automatically

**LuLu:**
- On first launch, approve the Network Extension prompt and restart when asked
- Choose whether to allow or block Apple/third-party connections during initial setup

**Pearcleaner:**
- On first launch, grant Full Disk Access and Accessibility when prompted
- Optionally enable the Sentinel Monitor (background watcher for app deletions) in Pearcleaner settings

**Screen Time — disable redundant built-in apps:**

The bootstrap script already deleted removable bloatware and rebuilt the Dock, but SIP-protected system apps (Calendar, Mail, Music, TV, News, Stocks, etc.) can't be deleted. Use Screen Time to functionally disable them:

1. Open **System Settings → Screen Time**
2. Turn on **App & Website Activity** if not already on
3. Go to **App Limits → Add Limit**
4. Select each app you want to disable: Calendar, Mail, Music, TV, News, Stocks, Freeform, Photo Booth, Chess, Automator
5. Set the time limit to **1 minute per day**
6. Set a **Screen Time passcode** (prevents bypassing the limit)

After the 1-minute limit is reached, the app grays out and won't launch without the passcode. This effectively disables the app while preserving SIP and your security posture.

### Step 7: Verify the setup

Run these checks to confirm everything is working:

```bash
# Shell tools
starship --version        # prompt
atuin --version           # shell history
zoxide --version          # smart cd
direnv --version          # per-directory env
fzf --version             # fuzzy finder
mise --version            # language versions

# Languages (managed by mise via ~/.config/mise/config.toml)
node --version            # Node.js LTS
python3 --version         # Python 3.12
go version                # Go latest
rustc --version           # Rust latest

# Modern CLI tools
bat --version             # cat replacement
eza --version             # ls replacement
fd --version              # find replacement
rg --version              # grep replacement
dust --version            # du replacement
trash --version           # safe rm

# Editor
nvim --version            # Neovim

# GitHub auth
gh auth status            # should show "Logged in"

# Commit signing (if configured)
ssh-add -l                # should list your signing key (if Bitwarden SSH agent enabled)
git config --get gpg.format  # should show "ssh" (if signing key was set)

# Dotfiles
chezmoi status            # should be empty if everything applied
chezmoi diff              # should show no differences
```

## Repo structure

```
.
├── bootstrap.sh           # The bootstrap script
└── README.md              # This file
```

Everything else lives in the [dotfiles repo](https://github.com/joshroy01/dotfiles), managed by chezmoi:

```
dotfiles/
├── Brewfile                        # Declarative package list
├── dot_config/
│   ├── zsh/
│   │   ├── .zshrc                  # Main shell config (OMZ + Starship + tools)
│   │   ├── exports/main.zsh        # PATH, FPATH, env vars
│   │   ├── aliases/main.zsh        # All aliases + compdef registrations
│   │   ├── functions/utils.zsh     # Utility functions
│   │   ├── completions/.keep       # Static completion files (generated, not tracked)
│   │   ├── dot_zcompcache/.keep    # Completion cache (generated, not tracked)
│   │   └── local.zsh               # Machine-specific overrides (not tracked)
│   ├── git/
│   │   └── allowed_signers         # SSH signing key → email mapping (templated)
│   ├── mise/config.toml            # Global language runtimes (node, python, go, rust)
│   ├── starship.toml               # Prompt theme
│   ├── nvim/                       # Neovim customizations (overlaid on LazyVim)
│   ├── aerospace/aerospace.toml    # Tiling window manager
│   └── karabiner/karabiner.json    # Keyboard customization
├── dot_gitconfig                   # Git settings (HTTPS transport, conditional signing)
├── dot_ssh/config                  # SSH host configurations
└── dot_zshenv                      # Sets ZDOTDIR to ~/.config/zsh
```

## Re-running after changes

If you update your dotfiles repo:

```bash
chezmoi update              # pull latest dotfiles and apply
```

If you update your Brewfile:

```bash
brew bundle install --file=~/.config/Brewfile    # install new packages
brew bundle cleanup --file=~/.config/Brewfile    # remove unlisted packages
```

If you install new CLI tools and need completions:

```bash
generate-completions        # regenerate static completion files + restart shell
```

To re-run the full bootstrap (safe to do anytime):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/joshroy01/bootstrap/main/bootstrap.sh)
```

## Troubleshooting

**GitHub authentication failed / browser didn't open**
If `gh auth login --web` can't open a browser (e.g., SSH session), authenticate manually:
```bash
gh auth login               # interactive mode with protocol selection
gh auth setup-git           # configure git credential helper
```
Then re-run the bootstrap script.

**"Brewfile contains Mac App Store apps"**
Open App Store and sign in with your Apple ID, then press Enter in the terminal to continue.

**`brew` not found after installation**
The script writes a temporary `~/.zprofile` with `brew shellenv` so Homebrew stays on PATH even if the script fails partway through and you open a new terminal. This file is cleaned up automatically once dotfiles are deployed. If you're in a session where `brew` still isn't found, source it manually:
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"    # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"       # Intel
```

**`_arguments:comparguments:327: can only be called from completion function`**
Stale completion cache. Run:
```bash
rebuild-completions         # clears cache + restarts shell
```

**Neovim plugins didn't install**
Open Neovim and run `:Lazy sync` manually. This downloads and installs all plugins.

**macOS defaults didn't take effect**
Some settings require a logout or restart. Log out and back in, or restart the Mac.

**AeroSpace / Karabiner not working**
Check System Settings → Privacy & Security. These apps need explicit Accessibility and/or Input Monitoring permissions.

**"Operation not permitted" errors from du, rsync, find**
Your terminal app needs Full Disk Access. System Settings → Privacy & Security → Full Disk Access → toggle on your terminal.

**Wrong font / broken icons in terminal**
Set your terminal font to a Nerd Font (JetBrains Mono Nerd Font or MesloLGS NF) in your terminal emulator's preferences. Run `generate-completions` if tab completion is broken.

**`trash` command not found**
The `trash` formula is keg-only. Verify `exports/main.zsh` adds `$HOMEBREW_PREFIX/opt/trash/bin` to PATH, then `exec zsh`.

**Completions not working for a tool**
Run `generate-completions` to regenerate static completion files. If a specific tool still lacks completions, check `$(brew --prefix)/share/zsh/site-functions/` for a `_toolname` file.

**Commit signing not working / "error: Load key" on commit**
Verify the Bitwarden SSH agent is running and your shell sees the key:
```bash
echo $SSH_AUTH_SOCK               # should show ~/.bitwarden-ssh-agent.sock
ssh-add -l                        # should list your signing key
git config --get user.signingKey  # should show your public key
```
If `SSH_AUTH_SOCK` is empty, ensure Bitwarden desktop is open with SSH Agent enabled and that `exports/main.zsh` has the socket export. If `ssh-add -l` shows nothing, unlock Bitwarden. If signing isn't configured in git, re-run `chezmoi init --force` and paste your public key when prompted.
