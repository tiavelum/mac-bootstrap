#!/bin/zsh
# install.sh — bootstrap a fresh Mac
# Pure zsh (ships with macOS), no Python or other runtime needed.
# Usage: ./install.sh

set -e

echo "==> Mac setup bootstrap"

# 1. Homebrew (the standard macOS package manager; only prerequisite)
if ! command -v brew >/dev/null 2>&1; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in this shell (Apple Silicon path)
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "==> Homebrew already installed"
fi

# 2. Apps from Brewfile
echo "==> Installing apps from Brewfile..."
brew bundle --file="$(dirname "$0")/Brewfile"

# 3. VS Code extensions
if command -v code >/dev/null 2>&1; then
  echo "==> Installing VS Code extensions..."
  code --install-extension anthropic.claude-code --force
else
  echo "!! 'code' command not found — open VS Code once, then rerun (or install the extension manually)"
fi

# 4. Manual steps (cannot be automated)
cat <<'EOF'

==> Done. Remaining manual steps:
  - Sign in: iCloud, OneDrive, WhatsApp (QR code), Chrome, Claude
  - GitHub token: generate at github.com/settings/tokens (classic, repo scope), use as git password once
  - Claude in Chrome extension: install from Chrome
  - Claude add-ins for Word/Excel: install from within Word/Excel
  - Claude Code in VS Code: log in with "Claude.ai Subscription"
  - Passwords app: syncs via Apple account automatically
EOF
