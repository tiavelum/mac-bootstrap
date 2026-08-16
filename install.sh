#!/bin/zsh
# install.sh — bootstrap a fresh Mac.
#
# ORCHESTRATION ONLY: preconditions, clones, and calls into other repos'
# installers. No mechanism of its own — a step that does real work inline
# belongs in a repo of its own. See setup-13 §3 in tiavelum/setup-docs.
# If you are about to add such a step here, that is the signal to create
# (or use) the repo it belongs to.
#
# Usage: ./install.sh

set -e

echo "==> Mac setup bootstrap"

# --- Preconditions ------------------------------------------------------
# Everything below is cloned from private repos, so both of these must be
# true before anything else can work. They used to live only in the README.

# 1. Homebrew — the one prerequisite nothing else can provide.
if ! command -v brew >/dev/null 2>&1; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"   # Apple Silicon path
else
  echo "==> Homebrew already installed"
fi

# 2. gh, authenticated. The full app list lives in a private repo, so gh
#    cannot come from it — it is installed directly here, ahead of the
#    clones, and appears in the Brewfile as well for completeness.
if ! command -v gh >/dev/null 2>&1; then
  echo "==> Installing gh..."
  brew install gh
fi

if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
!! Not authenticated with GitHub. Every repo below is private.
   Run this, choosing SSH when asked, then re-run this script:

     gh auth login

EOF
  exit 1
fi

# --- Repos --------------------------------------------------------------
echo "==> Cloning repos into ~/vc..."
mkdir -p "$HOME/vc"

clone_if_missing() {
  dest="$HOME/vc/$1"
  if [ -d "$dest/.git" ]; then
    echo "    $1 already cloned"
  elif git clone "git@github.com:tiavelum/$1.git" "$dest" 2>/dev/null; then
    echo "    cloned $1"
  else
    echo "!! could not clone $1" >&2
    return 1
  fi
}

# dotfiles first: it carries the config every later step reads.
clone_if_missing dotfiles           || true
clone_if_missing git-autosync       || true
clone_if_missing macprefs           || true
clone_if_missing macos-quick-actions || true
clone_if_missing setup-docs         || true

# --- Wiring: each repo installs itself ----------------------------------
if [ -f "$HOME/vc/dotfiles/install.sh" ]; then
  echo "==> dotfiles/install.sh"
  zsh "$HOME/vc/dotfiles/install.sh"
else
  echo "!! ~/vc/dotfiles/install.sh missing — git identity, aliases and the" >&2
  echo "   autosync repo list are NOT wired up" >&2
fi

if [ -f "$HOME/vc/git-autosync/install.sh" ]; then
  echo "==> git-autosync/install.sh"
  "$HOME/vc/git-autosync/install.sh"
fi

# macos-quick-actions has no installer yet — see open-items in setup-docs.
if [ -f "$HOME/vc/macos-quick-actions/install.sh" ]; then
  echo "==> macos-quick-actions/install.sh"
  "$HOME/vc/macos-quick-actions/install.sh"
fi

# --- Install what the config declares -----------------------------------
BREWFILE="$HOME/vc/dotfiles/Brewfile"
if [ -f "$BREWFILE" ]; then
  echo "==> brew bundle ($BREWFILE)"
  brew bundle --file="$BREWFILE"
else
  echo "!! $BREWFILE missing — no apps installed" >&2
fi

EXTENSIONS="$HOME/vc/dotfiles/vscode-extensions"
if [ -f "$EXTENSIONS" ] && command -v code >/dev/null 2>&1; then
  echo "==> VS Code extensions"
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$EXTENSIONS" | while IFS= read -r ext || [ -n "$ext" ]; do
    [ -n "$ext" ] || continue
    code --install-extension "$ext" --force
  done
elif [ -f "$EXTENSIONS" ]; then
  echo "!! 'code' not on PATH — open VS Code once, then re-run" >&2
fi

# --- Manual steps -------------------------------------------------------
cat <<'EOF'

==> Done. Remaining manual steps:
  - Clone any other repos named in ~/vc/dotfiles/git-autosync-repos
  - Sign in: iCloud, OneDrive, WhatsApp (QR code), Chrome, Claude
  - Claude in Chrome extension: install from Chrome
  - Claude add-ins for Word/Excel: install from within Word/Excel
  - Claude Code in VS Code: log in with "Claude.ai Subscription"
  - Logi Options+: reboot, then assign the MX Keys screenshot key
  - Maccy: launch at login, history size, hotkey
  - Passwords app: syncs via Apple account automatically

==> Verify:
  git alias | wc -l                        # 129
  git config user.email                    # from dotfiles/gitconfig
  readlink ~/.config/git-autosync/repos    # -> ~/vc/dotfiles/git-autosync-repos
  launchctl list | grep git-autosync
EOF
