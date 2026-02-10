# macOS Bootstrap

A single script that takes a fresh Mac from factory state to a fully configured development environment. Declarative, reproducible, and idempotent.

## What it does

The bootstrap script automates the following in order:

1. Installs Xcode Command Line Tools (provides `git`, `clang`, etc.)
2. Installs Homebrew
3. Installs chezmoi and clones your [dotfiles repo](https://github.com/joshroy01/dotfiles)
4. Applies dotfiles (places Brewfile, zshrc, starship config, etc.)
5. Installs all packages from Brewfile (CLI tools, casks, fonts, App Store apps)
6. Sets Homebrew zsh as the default shell
7. Configures macOS system defaults (Finder, Dock, keyboard, trackpad, screenshots, security)
8. Installs LazyVim starter and overlays Neovim customizations from dotfiles
9. Installs language runtimes via mise (Node, Python, Ruby, Go)
10. Installs Rust toolchain via rustup
11. Verifies shell tool installation (atuin, zoxide, direnv, starship, fzf, mise)

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
- **Default shell change** — prompts for your password once (`chsh` requires it).
- **Brewfile** — first run takes 10–30 minutes depending on your connection. Cask installs may trigger macOS security prompts.
- **Neovim plugins** — headless install runs silently. If it has issues, plugins finish installing on first launch.

The script is **idempotent** — you can re-run it safely. It skips steps that are already complete.

### Step 4: Restart your terminal

Close Terminal entirely and open your terminal emulator (iTerm2 or WezTerm, now installed by the Brewfile):

```bash
# Or from the existing terminal:
exec zsh
```

Your shell should now have Starship prompt, syntax highlighting, autosuggestions, and all tool integrations (atuin, zoxide, direnv, fzf, mise) active.

### Step 5: Grant app permissions

Several apps need macOS security permissions to function. Go to **System Settings → Privacy & Security** and grant access as prompted:

| App | Permission | Where to grant |
|-----|-----------|----------------|
| **AeroSpace** | Accessibility | Privacy & Security → Accessibility |
| **Karabiner-Elements** | Input Monitoring + Accessibility | Privacy & Security → Input Monitoring |
| **LuLu** | Network Extension | Privacy & Security → Network Extensions (requires restart) |

Each app will show a prompt on first launch asking you to open System Settings. Follow the prompts.

### Step 6: Configure apps that need manual setup

A few things can't be fully automated:

- **Bitwarden** — Sign in to the desktop app and browser extension. If you use the Bitwarden SSH agent, enable it in Settings → SSH Agent.
- **iTerm2 / WezTerm** — Set your font to **JetBrains Mono Nerd Font** in the terminal's preferences if it wasn't applied automatically.
- **AeroSpace** — Launch it once. The TOML config at `~/.config/aerospace/aerospace.toml` (managed by chezmoi) is picked up automatically.

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

# Languages
node --version            # Node.js
python3 --version         # Python
ruby --version            # Ruby
go version                # Go
rustc --version           # Rust

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

- `Brewfile` — declarative package list (CLI tools, casks, fonts, App Store apps)
- `.zshrc` — shell config with all tool init lines
- `.config/starship.toml` — prompt theme
- `.config/nvim/` — Neovim customizations (overlaid on LazyVim starter)
- `.config/aerospace/` — tiling window manager config
- `.gitconfig` — Git settings
- `.ssh/config` — SSH host configurations

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

**Neovim plugins didn't install**
Open Neovim and run `:Lazy sync` manually. This downloads and installs all plugins.

**macOS defaults didn't take effect**
Some settings require a logout or restart. Log out and back in, or restart the Mac.

**AeroSpace / Karabiner not working**
Check System Settings → Privacy & Security. These apps need explicit Accessibility and/or Input Monitoring permissions.

**Wrong font in terminal**
Set your terminal font to `JetBrains Mono Nerd Font` (or `JetBrainsMonoNerdFont-Regular`) in your terminal emulator's preferences.