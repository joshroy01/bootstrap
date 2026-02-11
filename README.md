# macOS Bootstrap

A single script that takes a fresh Mac from factory state to a fully configured development environment. Declarative, reproducible, and idempotent.

## What it does

The bootstrap script automates the following in order:

1. Installs Xcode Command Line Tools (provides `git`, `clang`, etc.)
2. Installs Homebrew
3. Installs chezmoi and clones your [dotfiles repo](https://github.com/joshroy01/dotfiles)
4. Applies dotfiles (places Brewfile, zshrc, mise config, starship config, etc.)
5. Installs all packages from Brewfile (CLI tools, casks, fonts, App Store apps)
6. Installs Oh-My-Zsh (framework for zsh plugins and completions)
7. Sets Homebrew zsh as the default shell (with ZDOTDIR → `~/.config/zsh/`)
8. Configures macOS system defaults (Finder, Dock, keyboard, trackpad, screenshots, security)
9. Creates PARA directory structure (`0-inbox` through `4-archive` + Developer workspace)
10. Installs LazyVim starter and overlays Neovim customizations from dotfiles
11. Installs language runtimes via mise (`~/.config/mise/config.toml`: Node, Python, Go, Rust)
12. Installs Rust components (rustfmt, clippy, rust-analyzer)
13. Generates static zsh completion files (gh, chezmoi, just, uv, rustup, cargo, starship, atuin, docker)
14. Verifies all shell tools are present

## Prerequisites

A Mac. That's it. Everything else is installed by the script.

If your dotfiles repo is **private**, you'll need a [GitHub personal access token](https://github.com/settings/tokens) ready to paste when prompted — or you can authenticate with the GitHub CLI first (the script will guide you if the clone fails).

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
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/joshroy01/bootstrap/main/bootstrap.sh)"
```

Or if you prefer to inspect before running:

```bash
curl -fsSL https://raw.githubusercontent.com/joshroy01/bootstrap/main/bootstrap.sh -o /tmp/bootstrap.sh
less /tmp/bootstrap.sh          # review it
bash /tmp/bootstrap.sh          # run it
```

**What to expect:**

- **Xcode CLI tools** — a system dialog will appear. Click "Install" and wait (2–5 minutes).
- **Homebrew** — prompts for your password once (needs `sudo` to create `/opt/homebrew`).
- **Private dotfiles repo** — if the clone fails, the script will tell you to run `brew install gh && gh auth login` and re-run.
- **Oh-My-Zsh** — installed with `KEEP_ZSHRC=yes` so it doesn't overwrite your chezmoi-managed `.zshrc`.
- **Default shell change** — prompts for your password once (`chsh` requires it).
- **Brewfile** — first run takes 10–30 minutes depending on your connection. Cask installs may trigger macOS security prompts.
- **mise runtimes** — installs Node, Python, Go, and Rust as defined in `~/.config/mise/config.toml` (applied by chezmoi).
- **Zsh completions** — generated as static files in `~/.config/zsh/completions/` for fast shell startup.
- **Neovim plugins** — headless install runs silently. If it has issues, plugins finish installing on first launch.

The script is **idempotent** — you can re-run it safely. It skips steps that are already complete.

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

**Atuin — shell history sync:**
```bash
atuin register   # create new account for cross-machine sync
# OR
atuin login      # log into existing account
# OR skip both to use atuin in offline-only mode
```

Atuin owns `Ctrl-R` (history search). fzf handles `Ctrl-T` (file search) and `Alt-C` (directory jump).

**Bitwarden:**
- Sign in to the desktop app and browser extension
- If you use the Bitwarden SSH agent, enable it in Settings → SSH Agent

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
│   ├── mise/config.toml            # Global language runtimes (node, python, go, rust)
│   ├── starship.toml               # Prompt theme
│   ├── nvim/                       # Neovim customizations (overlaid on LazyVim)
│   ├── aerospace/aerospace.toml    # Tiling window manager
│   └── karabiner/karabiner.json    # Keyboard customization
├── dot_gitconfig                   # Git settings
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

**"Failed to clone dotfiles repo"**
Your dotfiles repo is private and you haven't authenticated. Run:
```bash
brew install gh
gh auth login
```
Then re-run the bootstrap script.

**"Brewfile contains Mac App Store apps"**
Open App Store and sign in with your Apple ID, then press Enter in the terminal to continue.

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
Run `generate-completions` to regenerate static completion files. If a specific tool still lacks completions, check `brew --prefix)/share/zsh/site-functions/` for a `_toolname` file.
