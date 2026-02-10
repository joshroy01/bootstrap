#!/usr/bin/env bash
# ==============================================================================
# Bootstrap Script - First-Time Machine Setup
# ==============================================================================
# This script sets up a new macOS machine from scratch.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USER/dotfiles/main/bootstrap.sh | bash
#   OR
#   ./bootstrap.sh
#
# What it does (in order):
#   1. Installs Xcode Command Line Tools
#   2. Installs Homebrew
#   3. Installs chezmoi and applies dotfiles
#   4. Installs packages from Brewfile
#   5. Configures macOS defaults
#   6. Sets default shell to Homebrew zsh
#   7. Sets up Neovim with LazyVim
#   8. Sets up language runtimes (mise, Rust)
#   9. Verifies shell tool installation
#   10. Runs post-install hooks
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# Your dotfiles repo (update this!)
DOTFILES_REPO="https://github.com/joshroy01/dotfiles.git"

# Where chezmoi stores its source
CHEZMOI_SOURCE="$HOME/.local/share/chezmoi"

# Brewfile location (after chezmoi applies)
BREWFILE_PATH="$HOME/.config/Brewfile"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

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
# Preflight Checks
# ------------------------------------------------------------------------------

preflight_checks() {
    section "Preflight Checks"

    # Check macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        error "This script is designed for macOS only."
    fi
    success "Running on macOS $(sw_vers -productVersion)"

    # Check architecture
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
# Xcode Command Line Tools
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
# Homebrew
# ------------------------------------------------------------------------------

install_homebrew() {
    section "Homebrew"

    if command_exists brew; then
        success "Homebrew already installed"
        info "Updating Homebrew..."
        brew update
    else
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add to PATH for this session
        eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
        success "Homebrew installed"
    fi

    # Verify
    if ! command_exists brew; then
        error "Homebrew installation failed"
    fi

    brew --version
}

# ------------------------------------------------------------------------------
# Chezmoi & Dotfiles
# ------------------------------------------------------------------------------

install_chezmoi() {
    section "Chezmoi & Dotfiles"

    if ! command_exists chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    else
        success "Chezmoi already installed"
    fi

    # Initialize chezmoi with dotfiles repo
    if [[ -d "$CHEZMOI_SOURCE" ]]; then
        info "Chezmoi source already exists. Pulling latest..."
        chezmoi update
    else
        info "Initializing chezmoi from $DOTFILES_REPO..."
        if ! chezmoi init "$DOTFILES_REPO"; then
            echo ""
            warn "Failed to clone dotfiles repo."
            warn "If the repo is private, authenticate first:"
            echo "    brew install gh && gh auth login"
            echo "    # OR use a personal access token when prompted"
            echo ""
            warn "Then re-run this script."
            error "Cannot continue without dotfiles."
        fi
    fi

    success "Chezmoi initialized"
}

apply_dotfiles() {
    section "Applying Dotfiles"

    info "Running chezmoi apply..."
    chezmoi apply --verbose

    success "Dotfiles applied"
}

# ------------------------------------------------------------------------------
# Brewfile Installation
# ------------------------------------------------------------------------------

install_brewfile() {
    section "Installing Packages from Brewfile"

    if [[ ! -f "$BREWFILE_PATH" ]]; then
        error "Brewfile not found at $BREWFILE_PATH. Did chezmoi apply correctly?"
    fi

    # Check if Brewfile contains Mac App Store apps and user is signed in
    if grep -q '^mas ' "$BREWFILE_PATH"; then
        if ! command_exists mas || ! mas account &>/dev/null 2>&1; then
            warn "Brewfile contains Mac App Store apps."
            warn "Please sign in to the App Store before continuing."
            warn "Press Enter after signing in, or Ctrl+C to abort."
            read -r
        fi
    fi

    info "Installing packages from Brewfile..."
    info "This may take a while on first run..."

    brew bundle install --file="$BREWFILE_PATH" --verbose

    success "All packages installed"
}

# ------------------------------------------------------------------------------
# Shell Configuration
# ------------------------------------------------------------------------------

configure_shell() {
    section "Shell Configuration"

    local brew_zsh="$HOMEBREW_PREFIX/bin/zsh"

    # Check if Homebrew zsh is installed
    if [[ ! -x "$brew_zsh" ]]; then
        warn "Homebrew zsh not found. Skipping shell configuration."
        return
    fi

    # Add to /etc/shells if not present
    if ! grep -q "$brew_zsh" /etc/shells; then
        info "Adding $brew_zsh to /etc/shells..."
        echo "$brew_zsh" | sudo tee -a /etc/shells > /dev/null
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
# macOS Defaults
# ------------------------------------------------------------------------------

configure_macos_defaults() {
    section "macOS Defaults"

    info "Configuring macOS defaults..."

    # ── Finder ──────────────────────────────────────────────────────────────
    defaults write com.apple.finder AppleShowAllFiles -bool true           # Show hidden files
    defaults write com.apple.finder ShowPathbar -bool true                 # Show path bar
    defaults write com.apple.finder ShowStatusBar -bool true               # Show status bar
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true     # Full path in title
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"    # Search current folder
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
    defaults write com.apple.finder FXPreferredViewStyle -string "clmv"    # Column view

    # Show Library folder (hidden by default)
    chflags nohidden ~/Library

    # ── Dock ────────────────────────────────────────────────────────────────
    defaults write com.apple.dock autohide -bool true                      # Auto-hide dock
    defaults write com.apple.dock autohide-delay -float 0                  # No delay
    defaults write com.apple.dock autohide-time-modifier -float 0.3        # Animation speed
    defaults write com.apple.dock show-recents -bool false                 # No recent apps
    defaults write com.apple.dock tilesize -int 48                         # Icon size

    # ── Keyboard ────────────────────────────────────────────────────────────
    defaults write NSGlobalDomain KeyRepeat -int 2                         # Fast key repeat
    defaults write NSGlobalDomain InitialKeyRepeat -int 15                 # Short delay
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false     # Disable accent menu (essential for Vim)

    # ── Trackpad ────────────────────────────────────────────────────────────
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1       # Tap to click
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true  # Three-finger drag

    # ── Screenshots ─────────────────────────────────────────────────────────
    mkdir -p "$HOME/screenshots"
    defaults write com.apple.screencapture location -string "$HOME/screenshots"
    defaults write com.apple.screencapture type -string "png"
    defaults write com.apple.screencapture disable-shadow -bool true       # No shadow

    # ── Safari ──────────────────────────────────────────────────────────────
    defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
    defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

    # ── TextEdit ────────────────────────────────────────────────────────────
    defaults write com.apple.TextEdit RichText -bool false                 # Plain text default
    defaults write com.apple.TextEdit PlainTextEncoding -int 4             # UTF-8
    defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

    # ── Activity Monitor ────────────────────────────────────────────────────
    defaults write com.apple.ActivityMonitor ShowCategory -int 0           # All processes
    defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
    defaults write com.apple.ActivityMonitor SortDirection -int 0

    # ── Global / Misc ───────────────────────────────────────────────────────
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true        # Show extensions
    defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    # Expand save/print panels by default
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

    # Disable quarantine dialog for downloaded apps
    defaults write com.apple.LaunchServices LSQuarantine -bool false

    # Disable auto-correct, smart quotes, smart dashes (break code in terminal)
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

    # ── Security ────────────────────────────────────────────────────────────
    # Require password immediately after sleep/screensaver
    defaults write com.apple.screensaver askForPassword -int 1
    defaults write com.apple.screensaver askForPasswordDelay -int 0

    # ── Hot Corners ─────────────────────────────────────────────────────────
    # Bottom-right: Lock Screen (value 13) — fastest way to lock when stepping away
    defaults write com.apple.dock wvous-br-corner -int 13
    defaults write com.apple.dock wvous-br-modifier -int 0

    # ── Restart affected apps ───────────────────────────────────────────────
    for app in "Finder" "Dock" "SystemUIServer"; do
        killall "$app" &> /dev/null || true
    done

    success "macOS defaults configured"
    warn "Some changes may require a logout/restart to take effect"
}

# ------------------------------------------------------------------------------
# Neovim Configuration (LazyVim)
# ------------------------------------------------------------------------------

setup_neovim() {
    section "Neovim Configuration"

    if ! command_exists nvim; then
        warn "Neovim not installed. Skipping."
        return
    fi

    local nvim_config="$HOME/.config/nvim"
    local nvim_data="$HOME/.local/share/nvim"
    local nvim_state="$HOME/.local/state/nvim"
    local nvim_cache="$HOME/.cache/nvim"

    if [[ -d "$nvim_config" ]]; then
        success "Neovim config already exists at $nvim_config"
        info "To reset: rm -rf $nvim_config $nvim_data $nvim_state $nvim_cache"
        return
    fi

    # Step 1: Clone LazyVim starter (provides init.lua, lazy.lua,
    # .neoconf.json, stylua.toml, and empty config/plugin stubs)
    info "Cloning LazyVim starter..."
    git clone https://github.com/LazyVim/starter "$nvim_config"

    # Remove starter's git history — your dotfiles repo tracks customizations
    rm -rf "$nvim_config/.git"

    success "LazyVim starter installed at $nvim_config"

    # Step 2: Overlay chezmoi customizations (options.lua, keymaps.lua,
    # autocmds.lua, colorscheme.lua, editor.lua, lang.lua, etc.)
    if [[ -d "$CHEZMOI_SOURCE/dot_config/nvim" ]]; then
        info "Applying chezmoi nvim customizations over starter..."
        chezmoi apply --force "$HOME/.config/nvim"
        success "Custom nvim config applied"
    else
        info "No chezmoi nvim customizations found — using starter defaults"
    fi

    # Step 3: Headless plugin install (downloads all plugins without opening UI)
    info "Installing Neovim plugins headlessly (this may take a minute)..."
    nvim --headless "+Lazy! sync" +qa 2>/dev/null || {
        warn "Headless plugin install had issues. Plugins will finish installing on first launch."
    }

    success "Neovim configured with LazyVim"
}

# ------------------------------------------------------------------------------
# Language Version Manager (mise)
# ------------------------------------------------------------------------------

setup_mise() {
    section "Language Version Manager (mise)"

    if ! command_exists mise; then
        warn "mise not installed. Skipping language setup."
        return
    fi

    info "Configuring mise..."

    # Activate mise for this bash session (zsh activation is in .zshrc)
    eval "$(mise activate bash)"

    # Trust the global config
    mise trust --all 2>/dev/null || true

    # Install default language versions
    info "Installing default language runtimes..."

    # Node.js (LTS)
    info "  → Node.js LTS..."
    mise use --global node@lts

    # Python (latest stable)
    info "  → Python 3.12..."
    mise use --global python@3.12

    # Ruby (latest stable)
    info "  → Ruby 3.3..."
    mise use --global ruby@3.3

    # Go (latest)
    info "  → Go latest..."
    mise use --global go@latest

    success "mise configured with default languages"

    # Show what's installed
    info "Installed runtimes:"
    mise list
}

# ------------------------------------------------------------------------------
# Rust Setup (via rustup, not mise)
# ------------------------------------------------------------------------------

setup_rust() {
    section "Rust Toolchain"

    if command_exists rustup; then
        success "rustup already installed"
        info "Updating Rust toolchain..."
        rustup update stable
    elif command_exists rustup-init; then
        info "Initializing Rust toolchain..."
        rustup-init -y --no-modify-path
        source "$HOME/.cargo/env"
        success "Rust installed"
    else
        warn "rustup not found. Install via: brew install rustup"
        return
    fi

    # Install common components
    info "Installing Rust components..."
    rustup component add rustfmt clippy rust-analyzer

    success "Rust toolchain configured"
}

# ------------------------------------------------------------------------------
# Shell Tool Verification
# ------------------------------------------------------------------------------

verify_shell_tools() {
    section "Shell Tool Verification"

    # All shell tool init lines live in .zshrc (managed by chezmoi).
    # This section only verifies the binaries are present.

    local tools=(
        "atuin:shell history sync"
        "zoxide:smart cd"
        "direnv:per-directory env"
        "starship:shell prompt"
        "fzf:fuzzy finder"
        "mise:language version manager"
    )

    local missing=0
    for entry in "${tools[@]}"; do
        local tool="${entry%%:*}"
        local desc="${entry#*:}"
        if command_exists "$tool"; then
            success "$tool ($desc)"
        else
            warn "$tool ($desc) not found — check Brewfile"
            ((missing++)) || true
        fi
    done

    if [[ $missing -eq 0 ]]; then
        success "All shell tools installed"
    else
        warn "$missing tool(s) missing. They should be in your Brewfile."
    fi

    info "Shell tool init lines are in chezmoi-managed .zshrc — no manual setup needed"
}

# ------------------------------------------------------------------------------
# Post-Install Hooks
# ------------------------------------------------------------------------------

post_install() {
    section "Post-Install Tasks"

    # Verify fonts installed
    info "Verifying font installation..."
    if ls ~/Library/Fonts/JetBrainsMonoNerdFont* &> /dev/null; then
        success "JetBrains Mono Nerd Font installed"
    else
        warn "JetBrains Mono Nerd Font not found — check Brewfile"
    fi

    # AeroSpace permissions reminder
    if [[ -d "/Applications/AeroSpace.app" ]]; then
        warn "AeroSpace installed — grant Accessibility permissions in System Settings > Privacy & Security"
    fi

    # Karabiner permissions reminder
    if [[ -d "/Applications/Karabiner-Elements.app" ]]; then
        warn "Karabiner-Elements installed — grant permissions in System Settings > Privacy & Security"
    fi

    # LuLu permissions reminder
    if [[ -d "/Applications/LuLu.app" ]]; then
        warn "LuLu installed — grant Network Extension permissions in System Settings > Privacy & Security"
    fi
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
║  ✓ Xcode CLI Tools, Homebrew, chezmoi dotfiles                               ║
║  ✓ All Brewfile packages (CLI tools, casks, fonts, App Store apps)            ║
║  ✓ macOS defaults (Finder, Dock, keyboard, trackpad, security)               ║
║  ✓ Default shell → Homebrew zsh                                              ║
║  ✓ Neovim with LazyVim                                                       ║
║  ✓ Language runtimes via mise (Node, Python, Ruby, Go)                       ║
║  ✓ Rust toolchain via rustup                                                 ║
║  ✓ Shell tools verified (atuin, zoxide, direnv, starship, fzf, mise)         ║
║                                                                              ║
║  NEXT STEPS:                                                                 ║
║                                                                              ║
║  1. Restart your terminal (or run: exec zsh)                                 ║
║     All shell tool init lines are already in your .zshrc via chezmoi.        ║
║                                                                              ║
║  2. Grant permissions for apps that need them:                               ║
║     • AeroSpace → System Settings > Privacy & Security > Accessibility       ║
║     • Karabiner-Elements → System Settings > Privacy & Security              ║
║     • LuLu → System Settings > Privacy & Security > Network Extensions       ║
║                                                                              ║
║  3. First launch Neovim (plugins will finish setup):                         ║
║     nvim                                                                     ║
║                                                                              ║
║  USEFUL COMMANDS:                                                            ║
║     chezmoi diff          → See pending dotfile changes                      ║
║     chezmoi apply         → Apply dotfiles                                   ║
║     chezmoi update        → Pull & apply latest                              ║
║     brew bundle cleanup   → Remove unlisted packages                         ║
║     mise list             → See installed runtimes                           ║
║     mise use <tool>@<ver> → Install/switch versions                          ║
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

    preflight_checks
    install_xcode_cli
    install_homebrew
    install_chezmoi          # Clone dotfiles repo
    apply_dotfiles           # Put Brewfile + configs in place
    install_brewfile         # Install everything from Brewfile
    configure_shell          # Set Homebrew zsh as default
    configure_macos_defaults # Apply system preferences
    setup_neovim             # Install LazyVim + headless plugin sync
    setup_mise               # Install language runtimes
    setup_rust               # Install Rust toolchain
    verify_shell_tools       # Verify all shell tools present
    post_install             # Font check + permission reminders
    print_summary
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
