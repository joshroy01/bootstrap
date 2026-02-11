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
#   3.  Installs Homebrew
#   4.  Installs chezmoi and clones dotfiles
#   5.  Applies dotfiles (Brewfile, zshrc, mise config, starship, etc.)
#   6.  Installs packages from Brewfile
#   7.  Installs Oh-My-Zsh
#   8.  Sets default shell to Homebrew zsh
#   9.  Configures macOS defaults
#   10. Creates PARA directory structure
#   11. Sets up Neovim with LazyVim
#   12. Installs language runtimes (mise) + Rust components
#   13. Sets up zsh completion system
#   14. Verifies shell tool installation
#   15. Post-install hooks (fonts, permissions, atuin)
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

    if ! command_exists brew; then
        error "Homebrew installation failed"
    fi

    brew --version
}

# ------------------------------------------------------------------------------
# 4. Chezmoi & Dotfiles
# ------------------------------------------------------------------------------

install_chezmoi() {
    section "Chezmoi & Dotfiles"

    if ! command_exists chezmoi; then
        info "Installing chezmoi..."
        brew install chezmoi
    else
        success "Chezmoi already installed"
    fi

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

# ------------------------------------------------------------------------------
# 5. Brewfile Installation
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
    info "This may take 10–30 minutes on first run..."

    brew bundle install --file="$BREWFILE_PATH" --verbose

    # Handle keg-only formulae that need PATH
    if brew list trash &>/dev/null 2>&1; then
        success "trash (keg-only) installed — PATH handled in exports/main.zsh"
    fi

    success "All packages installed"
}

# ------------------------------------------------------------------------------
# 6. Oh-My-Zsh
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
# 7. Shell Configuration
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
# 8. macOS Defaults
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
    mkdir -p "$HOME/Screenshots"
    defaults write com.apple.screencapture location -string "$HOME/screenshots"
    defaults write com.apple.screencapture type -string "png"
    defaults write com.apple.screencapture disable-shadow -bool true

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
    for app in "Finder" "Dock" "SystemUIServer"; do
        killall "$app" &> /dev/null || true
    done

    success "macOS defaults configured"
    warn "Some changes may require a logout/restart to take effect"
}

# ------------------------------------------------------------------------------
# 9. PARA Directory Structure
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
# 10. Neovim Configuration (LazyVim)
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
        chezmoi apply --force "$HOME/.config/nvim"
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
# 11. Language Runtimes (mise)
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
# 12. Zsh Completion System
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
# 13. Shell Tool Verification
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
# 14. Post-Install Hooks
# ------------------------------------------------------------------------------

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
║  ✓ Oh-My-Zsh framework                                                      ║
║  ✓ Default shell → Homebrew zsh (ZDOTDIR → ~/.config/zsh)                    ║
║  ✓ macOS defaults (Finder, Dock, keyboard, trackpad, security)               ║
║  ✓ PARA directory structure (0-inbox through 4-archive + Developer)           ║
║  ✓ Neovim with LazyVim                                                       ║
║  ✓ Language runtimes via mise (Node, Python, Go, Rust)                       ║
║  ✓ Rust components (rustfmt, clippy, rust-analyzer)                          ║
║  ✓ Zsh static completions (gh, chezmoi, just, uv, rustup, etc.)             ║
║  ✓ Shell tools verified (starship, atuin, zoxide, direnv, fzf, mise)         ║
║                                                                              ║
║  NEXT STEPS:                                                                 ║
║                                                                              ║
║  1. Restart your terminal (or: exec zsh)                                     ║
║  2. Grant app permissions (see warnings above)                               ║
║  3. Grant Full Disk Access to your terminal app                              ║
║  4. Set up atuin (optional): atuin register OR atuin login                   ║
║  5. Set up Raycast as Spotlight replacement (see above)                      ║
║  6. Sign in to Bitwarden                                                     ║
║  7. First-launch Neovim: nvim (plugins finish setup)                         ║
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

    preflight_checks
    install_xcode_cli
    install_homebrew
    install_chezmoi
    apply_dotfiles
    install_brewfile
    install_oh_my_zsh
    configure_shell
    configure_macos_defaults
    create_directory_structure
    setup_neovim
    setup_mise
    setup_completions
    verify_shell_tools
    post_install
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
