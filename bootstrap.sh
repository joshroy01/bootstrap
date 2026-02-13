#!/usr/bin/env bash
# ==============================================================================
# Bootstrap Script - First-Time Machine Setup
# ==============================================================================
# This script sets up a new macOS machine from scratch.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/joshroy01/bootstrap/main/bootstrap.sh | bash
#   OR
#   ./bootstrap.sh
#
# What it does (in order):
#   1.  Preflight checks (macOS, architecture)
#   2.  Installs Xcode Command Line Tools
#   3.  Installs Homebrew (with bulletproof PATH setup + .zprofile bridge)
#   4.  Installs bootstrap dependencies (gh, chezmoi)
#   5.  Authenticates with GitHub (browser-based OAuth via gh)
#   6.  Clones dotfiles repo via chezmoi
#   7.  Applies dotfiles (Brewfile, zshrc, mise config, starship, etc.)
#   8.  Installs packages from Brewfile + re-evaluates chezmoi templates
#   9.  Removes pre-installed bloatware (iWork/iLife apps)
#   10. Disables built-in Apple apps (removes from Dock)
#   11. Installs Oh-My-Zsh
#   12. Sets default shell to Homebrew zsh
#   12b. Cleans up legacy zsh files (~/.zprofile, ~/.zshrc, etc.)
#   13. Configures macOS defaults (incl. 24hr time, power management)
#   14. Creates PARA directory structure
#   15. Sets up Neovim with LazyVim
#   16. Installs language runtimes (mise) + Rust components
#   17. Sets up zsh completion system
#   18. Verifies shell tool installation
#   19. Post-install hooks (fonts, permissions, atuin, Screen Time reminder)
#
# The script is idempotent — safe to re-run at any time.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

DOTFILES_REPO="https://github.com/joshroy01/dotfiles.git"
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"
BREWFILE_PATH="$HOME/.config/Brewfile"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

SSH_REWRITES=""

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

section() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

command_exists() {
    command -v "$1" &> /dev/null
}

# ------------------------------------------------------------------------------
# 1. Preflight Checks
# ------------------------------------------------------------------------------

preflight_checks() {
    section "Preflight Checks"

    if [[ "$(uname)" != "Darwin" ]]; then
        error "This script is designed for macOS only."
    fi
    success "Running on macOS $(sw_vers -productVersion)"

    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        HOMEBREW_PREFIX="/opt/homebrew"
        success "Detected Apple Silicon (arm64)"
    else
        HOMEBREW_PREFIX="/usr/local"
        success "Detected Intel (x86_64)"
    fi
    export HOMEBREW_PREFIX
}

# ------------------------------------------------------------------------------
# 2. Xcode Command Line Tools
# ------------------------------------------------------------------------------

install_xcode_cli() {
    section "Xcode Command Line Tools"

    if xcode-select -p &> /dev/null; then
        success "Xcode CLI tools already installed"
    else
        info "Installing Xcode Command Line Tools..."
        xcode-select --install

        # Wait for installation to complete
        until xcode-select -p &> /dev/null; do
            sleep 5
        done
        success "Xcode CLI tools installed"
    fi
}

# ------------------------------------------------------------------------------
# 3. Homebrew
# ------------------------------------------------------------------------------

install_homebrew() {
    section "Homebrew"

    # Check the known install path directly — not PATH, which isn't configured
    # yet in a fresh bash session. This prevents unnecessary reinstalls when
    # re-running the script after a partial failure.
    if [[ -x "$HOMEBREW_PREFIX/bin/brew" ]]; then
        success "Homebrew already installed"
        eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
        hash -r
        info "Updating Homebrew..."
        brew update
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        success "Homebrew installed"
    fi

    # Bulletproof PATH setup for this session.
    # eval "$(brew shellenv)" alone isn't enough — bash's command hash table
    # can cache old lookups, and the shell may not re-scan PATH immediately.
    # We source shellenv AND clear the hash, then verify with the absolute path.
    eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
    hash -r  # Clear bash's command lookup cache

    if ! command_exists brew; then
        # Last resort: force the absolute path into this session
        export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
        hash -r
    fi

    if ! command_exists brew; then
        error "Homebrew installation failed — brew not found in PATH"
    fi

    success "Homebrew on PATH: $(command -v brew)"
    brew --version

    # Persist brew shellenv for new terminal sessions opened between runs.
    # After a partial failure, the user may open a new terminal to debug —
    # without this, `brew` isn't on PATH because dotfiles (exports/main.zsh)
    # haven't been deployed yet. Once dotfiles are applied, exports/main.zsh
    # handles Homebrew PATH permanently and this bridge is cleaned up by
    # cleanup_legacy_zsh_files().
    local zprofile="$HOME/.zprofile"
    local shellenv_line="eval \"\$($HOMEBREW_PREFIX/bin/brew shellenv)\""

    if [[ ! -f "$zprofile" ]] || ! grep -qF "brew shellenv" "$zprofile"; then
        info "Adding brew shellenv to ~/.zprofile (temporary bridge)..."
        echo "$shellenv_line" >> "$zprofile"
        success "Homebrew PATH persisted in ~/.zprofile"
    fi
}

# ------------------------------------------------------------------------------
# 4. Bootstrap Dependencies (gh + chezmoi + mas)
# ------------------------------------------------------------------------------

install_bootstrap_deps() {
    section "Bootstrap Dependencies"

    # gh (GitHub CLI) — needed to authenticate with GitHub before cloning
    # private dotfiles repo. Must be installed BEFORE chezmoi init.
    if ! command_exists gh; then
        info "Installing GitHub CLI..."
        brew install gh
    else
        success "GitHub CLI already installed"
    fi

    # chezmoi — dotfiles manager
    if ! command_exists chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    else
        success "Chezmoi already installed"
    fi

    # mas (Mac App Store CLI) — needed to install Xcode before the Brewfile
    # runs, since Xcode license acceptance must happen before formulae that
    # depend on Xcode frameworks (swiftlint, swiftformat, gcc, llvm, etc.).
    if ! command_exists mas; then
        info "Installing mas (Mac App Store CLI)..."
        brew install mas
    else
        success "mas already installed"
    fi

    # Refresh hash after installing new binaries
    hash -r

    # Verify both are on PATH
    command_exists gh      || error "gh not found after install"
    command_exists chezmoi || error "chezmoi not found after install"

    success "gh $(gh --version | head -1 | awk '{print $3}')"
    success "chezmoi $(chezmoi --version | awk '{print $3}')"
}

# ------------------------------------------------------------------------------
# 5. GitHub Authentication
# ------------------------------------------------------------------------------

authenticate_github() {
    section "GitHub Authentication"

    # Check if already authenticated
    if gh auth status &>/dev/null 2>&1; then
        success "Already authenticated with GitHub"
        gh auth status 2>&1 | grep -E "Logged in|Token" | head -2 | while read -r line; do
            info "  $line"
        done
    else
        info "Authenticating with GitHub..."
        info "This will open a browser window for OAuth login."
        echo ""

        # --git-protocol https: avoids SSH key setup on a fresh machine.
        #   The dotfiles .gitconfig has SSH URL rewrites, but those aren't
        #   applied yet — we need HTTPS to work NOW for the initial clone.
        # --web: skips interactive protocol/host menus, goes straight to browser.
        # < /dev/tty: required when script is piped via curl | bash.
        gh auth login \
            --hostname github.com \
            --git-protocol https \
            --web \
            < /dev/tty

        if ! gh auth status &>/dev/null 2>&1; then
            error "GitHub authentication failed. Cannot clone private dotfiles repo."
        fi

        success "Authenticated with GitHub"
    fi

    # Configure git to use gh as credential helper.
    # This makes `git clone https://github.com/...` work for private repos
    # by delegating credential lookup to gh's OAuth token.
    gh auth setup-git
    success "Git credential helper configured (gh)"
}

# ------------------------------------------------------------------------------
# 6. Chezmoi & Dotfiles
# ------------------------------------------------------------------------------

install_chezmoi() {
    section "Chezmoi & Dotfiles"

    if [[ -d "$CHEZMOI_SOURCE" ]]; then
        info "Chezmoi source already exists. Pulling latest..."
        chezmoi update
    else
        info "Initializing chezmoi from $DOTFILES_REPO..."
        # < /dev/tty: chezmoi's promptStringOnce reads stdin for interactive
        # input. When running via `curl | bash`, stdin is the pipe.
        chezmoi init "$DOTFILES_REPO" < /dev/tty
    fi

    success "Chezmoi initialized"
}

apply_dotfiles() {
    section "Applying Dotfiles"

    info "Running chezmoi apply..."
    chezmoi apply --verbose --no-pager

    success "Dotfiles applied"

    # Verify critical files
    local critical_files=(
        "$HOME/.config/zsh/.zshrc"
        "$HOME/.config/Brewfile"
        "$HOME/.config/mise/config.toml"
    )
    for f in "${critical_files[@]}"; do
        if [[ -f "$f" ]]; then
            success "  ✓ $(basename "$f")"
        else
            warn "  ✗ $f not found — check chezmoi source"
        fi
    done
}

disable_git_ssh_rewrites() {
    section "Disabling Git SSH URL Rewrites"

    # Temporarily disable git SSH URL rewrites for Homebrew taps.
    # The .gitconfig may have multiple insteadOf values under the same
    # [url] section (e.g., https://github.com/ and gh:), so we must use
    # --get-all / --unset-all to handle them correctly.
    SSH_REWRITES=$(git config --global --get-all url.git@github.com:.insteadOf 2>/dev/null || true)

    if [[ -n "$SSH_REWRITES" ]]; then
        info "Temporarily disabling git SSH URL rewrite for Homebrew taps..."
        git config --global --unset-all url.git@github.com:.insteadOf
    fi
}

# ------------------------------------------------------------------------------
# 7. Brewfile Installation
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# 7a. Ensure Terminal App Management Permission
# ------------------------------------------------------------------------------

ensure_app_management_permission() {
    section "App Management Permission"

    # macOS Sequoia+ requires explicit App Management permission for any app
    # that installs .app bundles into /Applications/ (which brew cask does).
    # This can't be granted programmatically — TCC requires user interaction.
    # We trigger the prompt early with a no-op cask check so the user grants
    # it before the 30-minute Brewfile install starts.

    info "Homebrew cask installs require App Management permission."
    info "If prompted, click 'Allow' in the system dialog."
    echo ""

    # Trigger the permission prompt by attempting a cask operation.
    # 'brew list --cask' on an empty install will trigger it if the terminal
    # doesn't already have the permission.
    brew list --cask &>/dev/null 2>&1 || true

    # Verify the terminal can write to /Applications/
    local test_dir="/Applications/.bootstrap-permission-test"
    if mkdir "$test_dir" 2>/dev/null; then
        rmdir "$test_dir"
        success "Terminal has App Management permission"
    else
        warn "Terminal may not have App Management permission."
        warn "If cask installs fail, grant permission at:"
        info "  System Settings → Privacy & Security → App Management"
        info "  Toggle ON for: $(basename "$TERM_PROGRAM" 2>/dev/null || echo "Terminal")"
        echo ""
        warn "Press Enter to continue, or Ctrl+C to grant permission first."
        read -r < /dev/tty
    fi

    # Remind about WezTerm for future sessions
    echo ""
    info "After bootstrap completes, also grant App Management to WezTerm/Ghostty"
    info "if you plan to run 'brew install --cask' from those terminals."
    info "  System Settings → Privacy & Security → App Management"
}

# ------------------------------------------------------------------------------
# 7b. Install Packages from Brewfile
# ------------------------------------------------------------------------------

install_brewfile() {
    section "Installing Packages from Brewfile"

    # Install Xcode via Mac App Store before the Brewfile runs.
    # Xcode must be installed AND license-accepted before any formula that
    # links against Xcode frameworks (swiftlint, swiftformat, gcc, llvm, etc.).
    # Handling this outside the Brewfile avoids the mid-install license failure
    # that breaks all subsequent installs.
    if ! mdfind "kMDItemCFBundleIdentifier == com.apple.dt.Xcode" 2>/dev/null | grep -q "Xcode"; then
        info "Installing Xcode from Mac App Store (this may take a while)..."
        mas install 497799835  # Xcode
    else
        success "Xcode already installed"
    fi

    # Accept the Xcode license non-interactively.
    # This is required even if Xcode was already installed — a major version
    # update resets the license acceptance state.
    if /usr/bin/xcrun clang 2>&1 | grep -q "license"; then
        info "Accepting Xcode license..."
        sudo xcodebuild -license accept
        success "Xcode license accepted"
    else
        success "Xcode license already accepted"
    fi

    if [[ ! -f "$BREWFILE_PATH" ]]; then
        error "Brewfile not found at $BREWFILE_PATH. Did chezmoi apply correctly?"
    fi

    # Check if Brewfile contains Mac App Store apps and user is signed in
    if grep -q '^mas ' "$BREWFILE_PATH"; then
        if ! command_exists mas || ! mas account &>/dev/null 2>&1; then
            warn "Brewfile contains Mac App Store apps."
            warn "Please sign in to the App Store before continuing."
            warn "Press Enter after signing in, or Ctrl+C to abort."
            read -r < /dev/tty
        fi
    fi

    info "Installing packages from Brewfile..."
    info "This may take 10–30 minutes on first run..."

    # brew bundle returns non-zero if ANY package fails — even transient
    # download errors or upstream build issues. We capture the exit code
    # and report failures without killing the entire bootstrap, since later
    # stages (macOS defaults, neovim, mise, completions) are independent.
    local bundle_exit=0
    brew bundle install --file="$BREWFILE_PATH" --verbose || bundle_exit=$?

    # Handle keg-only formulae that need PATH
    if brew list trash &>/dev/null 2>&1; then
        success "trash (keg-only) installed — PATH handled in exports/main.zsh"
    fi

    if [[ $bundle_exit -ne 0 ]]; then
        warn "brew bundle exited with code $bundle_exit — some packages may have failed."
        warn "Review the output above and re-run after fixing:"
        info "  brew bundle install --file=$BREWFILE_PATH --verbose"
        echo ""
    else
        success "All packages installed"
    fi

    # Re-evaluate chezmoi templates now that all tools are installed.
    # First pass rendered templates with a partial toolchain (only gh + chezmoi).
    # Now delta, difft, cursor, nvim, etc. are installed, so lookPath calls
    # in .chezmoi.toml.tmpl and .gitconfig.tmpl will find them.
    info "Re-evaluating chezmoi templates with full toolchain..."
    chezmoi init --force       # Re-evaluate .chezmoi.toml.tmpl (editor detection)
    chezmoi apply --verbose --no-pager    # Re-render .gitconfig.tmpl (delta, gh, difft blocks)
    success "Dotfiles re-applied (templates now detect delta, gh, cursor, etc.)"

    info "Re-disabling git SSH URL rewrite for Homebrew taps..."
    git config --global --unset-all url.git@github.com:.insteadOf
}

# ------------------------------------------------------------------------------
# 8. Remove Pre-installed Bloatware
# ------------------------------------------------------------------------------

remove_bloatware() {
    section "Removing Pre-installed Apps"

    # These are App Store apps that come pre-installed — safe to delete.
    # macOS updates may occasionally re-install them; re-run to clean up.
    local apps=(
        "GarageBand"
        "iMovie"
        "Keynote"
        "Numbers"
        "Pages"
    )

    for app in "${apps[@]}"; do
        if [[ -d "/Applications/${app}.app" ]]; then
            sudo rm -rf "/Applications/${app}.app"
            success "Removed ${app}"
        else
            info "${app} already removed"
        fi
    done

    # Clean up GarageBand sound libraries (~2-3 GB)
    if [[ -d "/Library/Application Support/GarageBand" ]]; then
        sudo rm -rf "/Library/Application Support/GarageBand"
        sudo rm -rf "/Library/Audio/Apple Loops/Apple"
        success "Removed GarageBand sound libraries"
    fi

    success "Bloatware cleanup complete"
}

# ------------------------------------------------------------------------------
# 9. Disable Built-in Apple Apps
# ------------------------------------------------------------------------------

disable_builtin_apps() {
    section "Disabling Built-in Apple Apps"

    # Method 1: Remove from Dock
    # SIP-protected apps can't be deleted, but we can remove them from the Dock.
    # We rebuild the Dock's persistent-apps array with only the apps we want.

    # Clear the Dock entirely and rebuild with only apps we want.
    # This is cleaner than selectively removing entries.
    info "Rebuilding Dock with preferred apps only..."

    defaults write com.apple.dock persistent-apps -array

    # Add back the apps we actually want in the Dock
    local dock_apps=(
        "/Applications/Arc.app"
        "/System/Applications/System Settings.app"
        "/Applications/WezTerm.app"
        "/Applications/Ghostty.app"
        "/Applications/Cursor.app"
        "/Applications/Visual Studio Code.app"
        "/Applications/Obsidian.app"
        "/Applications/Notion.app"
        "/Applications/Notion Calendar.app"
        "/Applications/Readdle Spark.app"
        "/Applications/Slack.app"
        "/Applications/Discord.app"
        "/Applications/Spotify.app"
        "/Applications/Bitwarden.app"
    )

    for app_path in "${dock_apps[@]}"; do
        if [[ -d "$app_path" ]]; then
            defaults write com.apple.dock persistent-apps -array-add \
                "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file://${app_path}/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
        fi
    done

    killall Dock 2>/dev/null || true

    success "Dock rebuilt with preferred apps"

    # Method 2: Screen Time app limits (must be done manually)
    # Screen Time settings are SIP-protected and can't be set via defaults/CLI.
    echo ""
    warn "MANUAL STEP: Disable built-in apps via Screen Time"
    info "  System Settings → Screen Time → App & Website Activity (turn on)"
    info "  Then: App Limits → Add Limit → select these apps → set 1 min/day:"
    echo ""
    local disable_apps=(
        "Calendar"
        "Mail"
        "Music"
        "TV"
        "News"
        "Stocks"
        "Freeform"
        "Photo Booth"
        "Chess"
        "Automator"
    )
    for app in "${disable_apps[@]}"; do
        echo "    • $app"
    done
    echo ""
    info "  Set a Screen Time passcode to prevent accidental use."
    info "  This functionally disables apps without compromising SIP."
}

# ------------------------------------------------------------------------------
# 10. Oh-My-Zsh
# ------------------------------------------------------------------------------

install_oh_my_zsh() {
    section "Oh-My-Zsh"

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        success "Oh-My-Zsh already installed"
    else
        info "Installing Oh-My-Zsh..."
        # RUNZSH=no prevents it from switching to zsh mid-script
        # KEEP_ZSHRC=yes prevents it from overwriting our chezmoi-managed .zshrc
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        success "Oh-My-Zsh installed"
    fi
}

# ------------------------------------------------------------------------------
# 11. Shell Configuration
# ------------------------------------------------------------------------------

configure_shell() {
    section "Shell Configuration"

    local brew_zsh="$HOMEBREW_PREFIX/bin/zsh"

    if [[ ! -x "$brew_zsh" ]]; then
        warn "Homebrew zsh not found. Skipping shell configuration."
        return
    fi

    # Add to /etc/shells if not present
    if ! grep -q "$brew_zsh" /etc/shells; then
        info "Adding $brew_zsh to /etc/shells..."
        echo "$brew_zsh" | sudo tee -a /etc/shells > /dev/null
    fi

    # Set ZDOTDIR so zsh reads from ~/.config/zsh/ instead of ~/
    # This should already be in ~/.zshenv via chezmoi, but verify
    if [[ ! -f "$HOME/.zshenv" ]] || ! grep -q 'ZDOTDIR' "$HOME/.zshenv" 2>/dev/null; then
        info "Creating ~/.zshenv to set ZDOTDIR..."
        echo 'export ZDOTDIR="$HOME/.config/zsh"' > "$HOME/.zshenv"
        success "ZDOTDIR configured"
    else
        success "ZDOTDIR already set in ~/.zshenv"
    fi

    # Set as default shell
    if [[ "$SHELL" != "$brew_zsh" ]]; then
        info "Setting default shell to $brew_zsh..."
        chsh -s "$brew_zsh"
        success "Default shell changed (restart terminal to take effect)"
    else
        success "Default shell is already $brew_zsh"
    fi
}

# ------------------------------------------------------------------------------
# 11b. Clean Up Legacy Zsh Config Files
# ------------------------------------------------------------------------------

cleanup_legacy_zsh_files() {
    section "Cleaning Legacy Zsh Config Files"

    # ~/.zshenv is the ONE file we keep in $HOME — it sets ZDOTDIR to redirect
    # all other zsh config reads to ~/.config/zsh/. Everything else in $HOME is
    # either orphaned from a previous setup, created by Oh-My-Zsh install, or
    # a temporary bridge file (like the .zprofile Homebrew PATH shim).
    #
    # Zsh startup file load order (for reference):
    #   1. ~/.zshenv         (always, before ZDOTDIR takes effect) — WE KEEP THIS
    #   2. $ZDOTDIR/.zprofile (login shells)     — handled by exports/main.zsh
    #   3. $ZDOTDIR/.zshrc    (interactive shells) — managed by chezmoi
    #   4. $ZDOTDIR/.zlogin   (login shells)     — not used
    #   5. $ZDOTDIR/.zlogout  (on logout)        — not used
    #
    # Since ZDOTDIR=~/.config/zsh, any of these files in $HOME are dead weight
    # that zsh won't read but that clutter the home directory and could mask
    # bugs during testing.

    local legacy_files=(
        "$HOME/.zshrc"
        "$HOME/.zprofile"
        "$HOME/.zlogin"
        "$HOME/.zlogout"
        "$HOME/.zshrc.pre-oh-my-zsh"
    )

    local cleaned=0
    for f in "${legacy_files[@]}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            success "Removed $(basename "$f") (handled by ZDOTDIR config)"
            ((cleaned++))
        fi
    done

    # Stale completion dumps in $HOME (ours live in ~/.config/zsh/)
    for f in "$HOME"/.zcompdump*; do
        [[ -e "$f" ]] || continue
        rm -f "$f"
        success "Removed $(basename "$f") (stale completion cache)"
        ((cleaned++))
    done

    if [[ $cleaned -eq 0 ]]; then
        success "No legacy zsh files found — home directory clean"
    else
        success "Cleaned $cleaned legacy file(s) from home directory"
    fi
}

# ------------------------------------------------------------------------------
# 12. macOS Defaults
# ------------------------------------------------------------------------------

configure_macos_defaults() {
    section "macOS Defaults"

    info "Configuring macOS defaults..."

    # ── Finder ──────────────────────────────────────────────────────────────
    defaults write com.apple.finder AppleShowAllFiles -bool true
    defaults write com.apple.finder ShowPathbar -bool true
    defaults write com.apple.finder ShowStatusBar -bool true
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
    defaults write com.apple.finder FXPreferredViewStyle -string "clmv"

    chflags nohidden ~/Library

    # ── Dock ────────────────────────────────────────────────────────────────
    defaults write com.apple.dock autohide -bool true
    defaults write com.apple.dock autohide-delay -float 0
    defaults write com.apple.dock autohide-time-modifier -float 0.3
    defaults write com.apple.dock show-recents -bool false
    defaults write com.apple.dock tilesize -int 48

    # ── Keyboard ────────────────────────────────────────────────────────────
    defaults write NSGlobalDomain KeyRepeat -int 2
    defaults write NSGlobalDomain InitialKeyRepeat -int 15
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

    # ── Trackpad ────────────────────────────────────────────────────────────
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true

    # ── Screenshots ─────────────────────────────────────────────────────────
    mkdir -p "$HOME/screenshots"
    defaults write com.apple.screencapture location -string "$HOME/screenshots"
    defaults write com.apple.screencapture type -string "png"
    defaults write com.apple.screencapture disable-shadow -bool true

    # ── 24-Hour Time ────────────────────────────────────────────────────────
    # Set system-wide 24-hour clock (menu bar, lock screen, etc.)
    defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
    defaults write com.apple.menuextra.clock Show24Hour -bool true
    # Date format in menu bar: "EEE d MMM HH:mm:ss" = "Thu 12 Feb 14:30:00"
    defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM HH:mm:ss"

    # ── Power Management ────────────────────────────────────────────────────
    # Battery: aggressive display sleep to conserve battery
    #   Display off after 3 min, system sleep after 10 min
    sudo pmset -b displaysleep 3
    sudo pmset -b sleep 10
    sudo pmset -b lessbright 1       # Slightly dim on battery

    # Charger: relaxed — keep alive for long dev sessions
    #   Display off after 15 min, system never sleeps (0 = disabled)
    sudo pmset -c displaysleep 15
    sudo pmset -c sleep 0            # Never sleep on charger (useful for builds, downloads)

    # Shared settings (both battery and charger)
    sudo pmset -a lidwake 1          # Wake when lid opens
    sudo pmset -a powernap 0         # Disable Power Nap (prevents background wake)
    sudo pmset -a tcpkeepalive 1     # Keep network connections alive during sleep
    sudo pmset -a hibernatemode 3    # Safe Sleep: RAM + disk image (laptop default)

    # ── Safari ──────────────────────────────────────────────────────────────
    defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
    defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

    # ── TextEdit ────────────────────────────────────────────────────────────
    defaults write com.apple.TextEdit RichText -bool false
    defaults write com.apple.TextEdit PlainTextEncoding -int 4
    defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

    # ── Activity Monitor ────────────────────────────────────────────────────
    defaults write com.apple.ActivityMonitor ShowCategory -int 0
    defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
    defaults write com.apple.ActivityMonitor SortDirection -int 0

    # ── Global / Misc ───────────────────────────────────────────────────────
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

    defaults write com.apple.LaunchServices LSQuarantine -bool false

    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

    # ── Security ────────────────────────────────────────────────────────────
    defaults write com.apple.screensaver askForPassword -int 1
    defaults write com.apple.screensaver askForPasswordDelay -int 0

    # ── Hot Corners ─────────────────────────────────────────────────────────
    # Bottom-right: Lock Screen (value 13)
    defaults write com.apple.dock wvous-br-corner -int 13
    defaults write com.apple.dock wvous-br-modifier -int 0

    # ── Restart affected apps ───────────────────────────────────────────────
    for app in "Finder" "Dock" "SystemUIServer" "ControlCenter"; do
        killall "$app" &> /dev/null || true
    done

    success "macOS defaults configured (incl. 24hr time, power management)"
    warn "Some changes may require a logout/restart to take effect"
}

# ------------------------------------------------------------------------------
# 13. PARA Directory Structure
# ------------------------------------------------------------------------------

create_directory_structure() {
    section "Directory Structure"

    info "Creating PARA directories and dev workspace..."

    local dirs=(
        "$HOME/0-intake"
        "$HOME/1-projects"
        "$HOME/2-areas/finances"
        "$HOME/2-areas/government"
        "$HOME/2-areas/career"
        "$HOME/2-areas/education"
        "$HOME/2-areas/secrets"
        "$HOME/2-areas/health"
        "$HOME/2-areas/people"
        "$HOME/3-resources"
        "$HOME/4-archive"
        "$HOME/Developer/src/github.com/joshroy01"
        "$HOME/Developer/sandbox"
        "$HOME/Developer/learning"
        "$HOME/screenshots"
        "$HOME/.local/bin"
        "$HOME/.config/bin"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    success "Directory structure created"
}

# ------------------------------------------------------------------------------
# 14. Neovim Configuration (LazyVim)
# ------------------------------------------------------------------------------

setup_neovim() {
    section "Neovim Configuration"

    if ! command_exists nvim; then
        warn "Neovim not installed. Skipping."
        return
    fi

    local nvim_config="$HOME/.config/nvim"

    if [[ -d "$nvim_config" ]]; then
        success "Neovim config already exists at $nvim_config"
        info "To reset: rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim"
        return
    fi

    info "Cloning LazyVim starter..."
    git clone https://github.com/LazyVim/starter "$nvim_config"
    rm -rf "$nvim_config/.git"
    success "LazyVim starter installed"

    # Overlay chezmoi customizations if they exist
    if [[ -d "$CHEZMOI_SOURCE/dot_config/nvim" ]]; then
        info "Applying chezmoi nvim customizations..."
        chezmoi apply --force --no-pager "$HOME/.config/nvim"
        success "Custom nvim config applied"
    else
        info "No chezmoi nvim customizations found — using starter defaults"
    fi

    # Headless plugin install
    info "Installing Neovim plugins headlessly..."
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || {
        warn "Headless install had issues. Plugins will finish on first launch."
    }

    success "Neovim configured with LazyVim"
}

# ------------------------------------------------------------------------------
# 15. Language Runtimes (mise)
# ------------------------------------------------------------------------------

setup_mise() {
    section "Language Runtimes (mise)"

    if ! command_exists mise; then
        warn "mise not installed. Skipping language setup."
        return
    fi

    # Activate mise for this bash session (zsh activation is in .zshrc)
    eval "$(mise activate bash)"

    # Trust the global config (applied by chezmoi at ~/.config/mise/config.toml)
    mise trust --all 2>/dev/null || true

    # Install runtimes defined in config.toml (node, python, go, rust)
    info "Installing runtimes from ~/.config/mise/config.toml..."
    mise install --yes

    success "mise runtimes installed"

    # Rust components — mise installs the toolchain via its rust backend,
    # but we need these additional components for development
    if command_exists rustup; then
        info "Installing Rust components (rustfmt, clippy, rust-analyzer)..."
        rustup component add rustfmt clippy rust-analyzer 2>/dev/null || {
            warn "Could not install Rust components. Run manually: rustup component add rustfmt clippy rust-analyzer"
        }
        success "Rust components installed"
    fi

    info "Installed runtimes:"
    mise list
}

# ------------------------------------------------------------------------------
# 16. Install usql
# ------------------------------------------------------------------------------

install_usql() {
    # usql — universal SQL CLI. Installed via go install instead of Homebrew
    # because the xo/xo tap formula builds with the 'most' tag, which pulls
    # in cockroachdb/swiss and fails due to Go version incompatibilities.
    # Base drivers (PostgreSQL, MySQL, SQLite3, MSSQL, Oracle, CSVQ) cover
    # all databases in our Brewfile.
    if ! command_exists usql; then
        info "Installing usql via go install (base drivers)..."
        go install -tags 'redis mongodb' github.com/xo/usql@master 2>/dev/null && {
            success "usql installed (base drivers: pg, my, sqlite3, mssql, oracle, csvq)"
        } || {
            warn "usql install failed — install manually: go install github.com/xo/usql@master"
        }
    else
        success "usql already installed"
    fi
}

# ------------------------------------------------------------------------------
# 17. Zsh Completion System
# ------------------------------------------------------------------------------

setup_completions() {
    section "Zsh Completion System"

    # Create directories (also tracked via chezmoi .keep files)
    mkdir -p "$HOME/.config/zsh/completions"
    mkdir -p "$HOME/.config/zsh/.zcompcache"
    success "Completion directories created"

    # Generate static completion files for tools that support it.
    # This writes _tool files into ~/.config/zsh/completions/ (in FPATH)
    # so compinit picks them up — no slow eval on every shell startup.
    info "Generating static completion files..."

    local comp_dir="$HOME/.config/zsh/completions"
    local generated=0

    if command_exists gh; then
        gh completion -s zsh > "$comp_dir/_gh" 2>/dev/null && { success "  ✓ gh"; ((generated++)); }
    fi
    if command_exists chezmoi; then
        chezmoi completion zsh > "$comp_dir/_chezmoi" 2>/dev/null && { success "  ✓ chezmoi"; ((generated++)); }
    fi
    if command_exists just; then
        just --completions zsh > "$comp_dir/_just" 2>/dev/null && { success "  ✓ just"; ((generated++)); }
    fi
    if command_exists uv; then
        uv generate-shell-completion zsh > "$comp_dir/_uv" 2>/dev/null && { success "  ✓ uv"; ((generated++)); }
    fi
    if command_exists rustup; then
        rustup completions zsh > "$comp_dir/_rustup" 2>/dev/null && { success "  ✓ rustup"; ((generated++)); }
        rustup completions zsh cargo > "$comp_dir/_cargo" 2>/dev/null && { success "  ✓ cargo"; ((generated++)); }
    fi
    if command_exists starship; then
        starship completions zsh > "$comp_dir/_starship" 2>/dev/null && { success "  ✓ starship"; ((generated++)); }
    fi
    if command_exists atuin; then
        atuin gen-completions --shell zsh --out-dir "$comp_dir" 2>/dev/null && { success "  ✓ atuin"; ((generated++)); }
    fi
    if command_exists docker; then
        docker completion zsh > "$comp_dir/_docker" 2>/dev/null && { success "  ✓ docker"; ((generated++)); }
    fi

    # Clear stale completion cache
    rm -f "$HOME/.zcompdump"* 2>/dev/null || true
    rm -f "$HOME/.config/zsh/.zcompdump"* 2>/dev/null || true

    success "$generated completion files generated"
    info "Completions will be picked up on first zsh startup"
}

# ------------------------------------------------------------------------------
# 18. Shell Tool Verification
# ------------------------------------------------------------------------------

verify_shell_tools() {
    section "Shell Tool Verification"

    local tools=(
        "starship:shell prompt"
        "atuin:shell history sync"
        "zoxide:smart cd"
        "direnv:per-directory env"
        "fzf:fuzzy finder"
        "mise:language version manager"
        "bat:modern cat"
        "eza:modern ls"
        "fd:modern find"
        "rg:modern grep"
        "dust:modern du"
        "trash:safe rm"
        "lazygit:git TUI"
        "chezmoi:dotfiles manager"
        "nvim:editor"
    )

    local missing=0
    for entry in "${tools[@]}"; do
        local tool="${entry%%:*}"
        local desc="${entry#*:}"
        if command_exists "$tool"; then
            success "$tool ($desc)"
        else
            warn "$tool ($desc) — not found"
            ((missing++)) || true
        fi
    done

    if [[ $missing -eq 0 ]]; then
        success "All shell tools installed"
    else
        warn "$missing tool(s) missing — check Brewfile"
    fi
}

# ------------------------------------------------------------------------------
# 19. Post-Install Hooks
# ------------------------------------------------------------------------------

restore_git_ssh_rewrites() {
    section "Restoring Git SSH URL Rewrites"

    # Restore all SSH rewrites now that clones are complete
    if [[ -n "$SSH_REWRITES" ]]; then
        info "Restoring Git SSH URL rewrites..."
        while IFS= read -r rewrite; do
            git config --global --add url.git@github.com:.insteadOf "$rewrite"
        done <<< "$SSH_REWRITES"
        success "Git SSH URL rewrites restored"
    else
        success "No Git SSH URL rewrites to restore"
    fi
}

post_install() {
    section "Post-Install Tasks"

    # Font verification
    info "Checking Nerd Font installation..."
    if ls ~/Library/Fonts/*NerdFont* &> /dev/null 2>&1; then
        success "Nerd Font installed"
    else
        warn "No Nerd Font found — install via Brewfile cask or manually"
        warn "Starship prompt needs a Nerd Font for icons to render"
    fi

    # Permission reminders for security-sensitive apps
    echo ""
    info "The following apps need manual permission grants:"
    echo ""

    local permission_apps=(
        "AeroSpace.app:Accessibility:System Settings → Privacy & Security → Accessibility"
        "Karabiner-Elements.app:Accessibility + Input Monitoring:System Settings → Privacy & Security"
        "Raycast.app:Accessibility:System Settings → Privacy & Security → Accessibility"
        "LuLu.app:Network Extension:System Settings → Privacy & Security (requires restart)"
        "Pearcleaner.app:Full Disk Access + Accessibility:System Settings → Privacy & Security"
        "Logi Options+.app:Input Monitoring:System Settings → Privacy & Security → Input Monitoring"
    )

    for entry in "${permission_apps[@]}"; do
        local app="${entry%%:*}"
        local perms="${entry#*:}"
        local perm_type="${perms%%:*}"
        local path="${perms#*:}"
        if [[ -d "/Applications/$app" ]]; then
            warn "  $app → $perm_type"
            info "    $path"
        fi
    done

    # Terminal Full Disk Access reminder
    echo ""
    warn "Grant Full Disk Access to your terminal app (iTerm2, WezTerm, Ghostty)"
    info "  System Settings → Privacy & Security → Full Disk Access"
    info "  This allows tools like du, rsync, and backup scripts to access all directories"

    echo ""
    warn "Grant App Management permission to your terminal apps (WezTerm, Ghostty)"
    info "  WezTerm.app:App Management:System Settings → Privacy & Security → App Management"
    info "  Ghostty.app:App Management:System Settings → Privacy & Security → App Management"
    info "  This allows the terminal apps to manage other apps"

    # Atuin setup
    echo ""
    if command_exists atuin; then
        info "Atuin shell history is installed. To set up sync:"
        echo "    atuin register    # create new account"
        echo "    atuin login       # log into existing account"
        echo "  Or skip both to use atuin in offline-only mode."
    fi

    # Raycast setup
    echo ""
    if [[ -d "/Applications/Raycast.app" ]]; then
        info "Raycast — to replace Spotlight:"
        echo "    1. System Settings → Keyboard → Keyboard Shortcuts → Spotlight"
        echo "    2. Uncheck 'Show Spotlight search' (frees Cmd+Space)"
        echo "    3. Raycast Settings → General → set hotkey to Cmd+Space"
        echo "    4. Enable 'Launch at Login' in Raycast settings"
    fi

    # Bitwarden setup
    echo ""
    if [[ -d "/Applications/Bitwarden.app" ]]; then
        info "Bitwarden — sign in to desktop app and browser extension"
        info "  If using SSH agent: Settings → SSH Agent → Enable"
    fi

    # Screen Time app disabling reminder
    echo ""
    warn "REMINDER: Disable redundant built-in apps via Screen Time"
    info "  The bootstrap script already removed bloatware and rebuilt the Dock."
    info "  For SIP-protected apps (Calendar, Mail, Music, TV, News, Stocks, etc.):"
    info "  System Settings → Screen Time → App Limits → Add Limit → 1 min/day"
    info "  Set a Screen Time passcode to enforce the limit."
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

print_summary() {
    section "Setup Complete!"

    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║  Your machine is now configured!                                             ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  WHAT WAS SET UP:                                                            ║
║                                                                              ║
║  ✓ Xcode CLI Tools, Homebrew (with PATH configured)                          ║
║  ✓ GitHub CLI authenticated + git credential helper                          ║
║  ✓ Chezmoi dotfiles cloned, applied, and re-evaluated                        ║
║  ✓ All Brewfile packages (CLI tools, casks, fonts, App Store apps)           ║
║  ✓ Removed bloatware (GarageBand, iMovie, Keynote, Numbers, Pages)           ║
║  ✓ Rebuilt Dock with preferred apps, disabled redundant built-in apps        ║
║  ✓ Oh-My-Zsh framework                                                       ║
║  ✓ Default shell → Homebrew zsh (ZDOTDIR → ~/.config/zsh)                    ║
║  ✓ Cleaned legacy zsh files from $HOME (.zprofile, .zshrc, .zcompdump, etc.) ║
║  ✓ macOS defaults (Finder, Dock, keyboard, trackpad, security)               ║
║  ✓ 24-hour time (menu bar, lock screen, system-wide)                         ║
║  ✓ Power management (battery: 3m display/10m sleep, charger: 15m/never)      ║
║  ✓ PARA directory structure (0-inbox through 4-archive + Developer)          ║
║  ✓ Neovim with LazyVim                                                       ║
║  ✓ Language runtimes via mise (Node, Python, Go, Rust)                       ║
║  ✓ Rust components (rustfmt, clippy, rust-analyzer)                          ║
║  ✓ Zsh static completions (gh, chezmoi, just, uv, rustup, etc.)              ║
║  ✓ Shell tools verified (starship, atuin, zoxide, direnv, fzf, mise)         ║
║                                                                              ║
║  NEXT STEPS:                                                                 ║
║                                                                              ║
║  1. Restart your terminal (or: exec zsh)                                     ║
║  2. Grant app permissions (see warnings above)                               ║
║  3. Grant Full Disk Access to your terminal app                              ║
║  4. Disable built-in apps via Screen Time (see warnings above)               ║
║  5. Set up atuin (optional): atuin register OR atuin login                   ║
║  6. Set up Raycast as Spotlight replacement (see above)                      ║
║  7. Sign in to Bitwarden                                                     ║
║  8. First-launch Neovim: nvim (plugins finish setup)                         ║
║                                                                              ║
║  USEFUL COMMANDS:                                                            ║
║     chezmoi diff              → See pending dotfile changes                  ║
║     chezmoi apply             → Apply dotfiles                               ║
║     chezmoi update            → Pull & apply latest                          ║
║     brew bundle cleanup       → Remove unlisted packages                     ║
║     mise list                 → See installed runtimes                       ║
║     generate-completions      → Regenerate zsh completions (in zsh)          ║
║     rebuild-completions       → Clear completion cache (in zsh)              ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              macOS Bootstrap Script                              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Prompt for sudo upfront and keep the credential cached for the
    # duration of the script. Prevents repeated password prompts when
    # sudo calls are spread across stages separated by long installs.
    sudo -v
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

    preflight_checks
    install_xcode_cli
    install_homebrew
    install_bootstrap_deps
    authenticate_github
    install_chezmoi
    apply_dotfiles
    disable_git_ssh_rewrites
    ensure_app_management_permission
    install_brewfile
    remove_bloatware
    disable_builtin_apps
    install_oh_my_zsh
    configure_shell
    cleanup_legacy_zsh_files
    configure_macos_defaults
    create_directory_structure
    setup_neovim
    setup_mise
    install_usql
    setup_completions
    verify_shell_tools
    restore_git_ssh_rewrites
    post_install
    print_summary
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    main "$@"
fi
