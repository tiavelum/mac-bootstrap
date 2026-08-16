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

# 3a. Refuse to guess a git identity.
#     Left to itself, git invents "Full Name <user@hostname>" from the OS
#     account, prints one hint, and commits — GitHub cannot attribute those
#     commits, and nobody notices, least of all when the committer is an
#     unattended script. The identity itself lives in dotfiles/gitconfig
#     (step 4a); this setting is what makes a broken include loud instead
#     of silent, so it is written here, into ~/.gitconfig, and must NOT be
#     moved into the included file.
git config --global user.useConfigOnly true

# 4. Config and sync repos under ~/vc
#    dotfiles     = personal config (gitconfig: identity + aliases;
#                   git-autosync repo list)
#    git-autosync = the sync tool itself
#    Both are cloned rather than vendored here: config lives apart from
#    the scripts that use it.
echo "==> Setting up ~/vc repos..."
mkdir -p "$HOME/vc"

clone_if_missing() {
  name="$1"; url="$2"; dest="$HOME/vc/$1"
  if [ -d "$dest/.git" ]; then
    echo "    $name already cloned"
  elif git clone "$url" "$dest" 2>/dev/null; then
    echo "    cloned $name"
  else
    echo "!! could not clone $name — run 'gh auth login' first, then rerun this script" >&2
    return 1
  fi
}

clone_if_missing dotfiles     git@github.com:tiavelum/dotfiles.git     || true
clone_if_missing git-autosync git@github.com:tiavelum/git-autosync.git || true

# 4a. Git identity and aliases — included live from the dotfiles clone,
#     never copied. A missing include is skipped by git in silence, so
#     check the file and then check the effect.
if [ -f "$HOME/vc/dotfiles/gitconfig" ]; then
  git config --global include.path "$HOME/vc/dotfiles/gitconfig"
  echo "    git config included: $(git config user.name) <$(git config user.email)>, $(git alias 2>/dev/null | wc -l | tr -d ' ') aliases"
else
  echo "!! ~/vc/dotfiles/gitconfig missing — no identity, no aliases." >&2
  echo "   git will refuse to commit (useConfigOnly) rather than guess. Clone dotfiles." >&2
fi

# 4b. git-autosync reads its repo list from ~/.config; symlink it at the
#     versioned copy so the list is never a machine-local orphan again.
if [ -f "$HOME/vc/dotfiles/git-autosync-repos" ]; then
  mkdir -p "$HOME/.config/git-autosync"
  ln -sfn "$HOME/vc/dotfiles/git-autosync-repos" "$HOME/.config/git-autosync/repos"
  echo "    git-autosync repo list symlinked into dotfiles"
else
  echo "!! ~/vc/dotfiles/git-autosync-repos missing — git-autosync would sync nothing" >&2
fi

if [ -f "$HOME/vc/git-autosync/install.sh" ]; then
  echo "==> Installing git-autosync agents..."
  "$HOME/vc/git-autosync/install.sh"
fi

# 5. Manual steps (cannot be automated)
cat <<'EOF'

==> Done. Remaining manual steps:
  - GitHub first: 'gh auth login' (SSH) — do this before step 4 works
  - Clone the remaining repos named in ~/vc/dotfiles/git-autosync-repos
  - Sign in: iCloud, OneDrive, WhatsApp (QR code), Chrome, Claude
  - Claude in Chrome extension: install from Chrome
  - Claude add-ins for Word/Excel: install from within Word/Excel
  - Claude Code in VS Code: log in with "Claude.ai Subscription"
  - Passwords app: syncs via Apple account automatically

==> Verify:
  git alias | wc -l                        # 129
  git config user.email                    # from dotfiles/gitconfig, not empty
  readlink ~/.config/git-autosync/repos    # -> ~/vc/dotfiles/git-autosync-repos
  launchctl list | grep git-autosync
EOF
