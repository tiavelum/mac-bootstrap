#!/bin/zsh
# bootstrap.sh — bootstrap a fresh Mac.
#
# ORCHESTRATION ONLY: preconditions, clones, and calls into other repos'
# installers. No mechanism of its own — a step that does real work inline
# belongs in a repo of its own. If you are about to add such a step here,
# that is the signal to create (or use) the repo it belongs to.
#
# The stages below are ordered by dependency, and the order is not free:
#   brew -> gh -> gh auth -> clone -> wire config -> apps -> preferences
# Stage 7 installs the transport that publishes local commits. It is
# deliberately last and skippable: a Mac is fully usable without it, and
# it is not needed to work on unrelated repos. Two things depend on it —
# Claude sessions working in these clones, and the macprefs snapshot
# agent publishing its snapshots.
#
# Usage: ./bootstrap.sh [--skip-transport]

set -e

SKIP_TRANSPORT=0
for arg in "$@"; do
  case "$arg" in
    --skip-transport) SKIP_TRANSPORT=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "==> Mac setup bootstrap"

# --- Stage 1: preconditions ---------------------------------------------
# Everything below is cloned from private repos, so both of these must be
# true before anything else can work.
#
# The deliberate circular dependency, and how it is broken: the app list
# (Brewfile) lives in a private repo that cannot be cloned without an
# authenticated gh — so gh is installed directly here, ahead of every
# clone, rather than coming from the list it is needed to fetch.

echo "==> [1/7] Preconditions"

# Xcode command line tools: git itself comes from here on a bare machine,
# and Homebrew's own installer needs them too. The install is a GUI dialog,
# so the script cannot wait it out — it stops and asks you to come back.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "    Xcode command line tools missing"
  xcode-select --install 2>/dev/null || true
  echo "!! A macOS dialog has opened. Finish that install, then re-run this script." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "    installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"   # Apple Silicon path
else
  echo "    Homebrew already installed"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "    installing gh..."
  brew install gh
fi

if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
!! Not authenticated with GitHub. Every repo below is private.
   Run this, choosing GitHub.com / SSH / browser, then re-run this script:

     gh auth login

EOF
  exit 1
fi

# --- Stage 2: clone -----------------------------------------------------
echo "==> [2/7] Cloning repos into ~/vc"
mkdir -p "$HOME/vc"

failed_clones=""

clone_if_missing() {
  dest="$HOME/vc/$1"
  if [ -d "$dest/.git" ]; then
    echo "    $1 already cloned"
  elif git clone --quiet "git@github.com:tiavelum/$1.git" "$dest"; then
    echo "    cloned $1"
  else
    echo "!! could not clone $1" >&2
    failed_clones="$failed_clones $1"
  fi
}

# machine-config first: it carries the config every later stage reads.
clone_if_missing machine-config
# Tools that install or are invoked by later stages.
clone_if_missing macprefs                      # stage 6 needs the tool
clone_if_missing macprefs-config               # ... and its snapshots
clone_if_missing macos-quick-actions
# On-demand tools: no installer, run from the clone when needed.
clone_if_missing doc-convert
clone_if_missing vcard-merge
# Knowledge, and the convention it follows.
clone_if_missing setup-docs
clone_if_missing agent-memory
# Transport for stage 7; cloned here so the repo list is complete either way.
clone_if_missing git-autosync

# --- Stage 3: wire the config -------------------------------------------
# Each repo installs itself; this script only calls.
echo "==> [3/7] Wiring config"

if [ -f "$HOME/vc/machine-config/install.sh" ]; then
  zsh "$HOME/vc/machine-config/install.sh" || echo "!! machine-config/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/machine-config/install.sh missing — git identity, aliases and the" >&2
  echo "   autosync repo list are NOT wired up" >&2
fi

# --- Stage 4: install what the config declares --------------------------
echo "==> [4/7] Apps and packages"

BREWFILE="$HOME/vc/machine-config/Brewfile"
if [ -f "$BREWFILE" ]; then
  brew bundle --file="$BREWFILE" || echo "!! brew bundle reported errors — one unavailable cask is enough" >&2
else
  echo "!! $BREWFILE missing — no apps installed" >&2
fi

EXTENSIONS="$HOME/vc/machine-config/vscode-extensions"
if [ -f "$EXTENSIONS" ] && command -v code >/dev/null 2>&1; then
  echo "    VS Code extensions"
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$EXTENSIONS" | while IFS= read -r ext || [ -n "$ext" ]; do
    [ -n "$ext" ] || continue
    code --install-extension "$ext" --force
  done
elif [ -f "$EXTENSIONS" ]; then
  echo "!! 'code' not on PATH — open VS Code once, then re-run" >&2
fi

# Default applications, last in this stage: the bindings name applications
# that must already exist, and duti itself comes from the Brewfile above.
DEFAULTS="$HOME/vc/machine-config/apply-default-apps.sh"
if [ -f "$DEFAULTS" ]; then
  "$DEFAULTS" || echo "!! default applications not fully applied — see above" >&2
fi

# --- Stage 5: tools that install themselves -----------------------------
echo "==> [5/7] Tools"

# Installs the Finder services and builds Control Center Toggle.app, the
# application that holds the Accessibility grant for the Control Center
# hotkey. Granting that permission and binding the key stay manual.
if [ -f "$HOME/vc/macos-quick-actions/install.sh" ]; then
  "$HOME/vc/macos-quick-actions/install.sh" || echo "!! macos-quick-actions/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/macos-quick-actions/install.sh missing — Finder services not installed" >&2
fi

# --- Stage 6: preferences -----------------------------------------------
# Must come after the apps exist: restoring a preference domain for an app
# that is not installed writes a plist nothing will read.
#
# The restore itself is NOT run automatically. It overwrites live settings
# on a machine you may already have configured, so it stays a deliberate,
# explicit command.
echo "==> [6/7] Preferences"

if [ -d "$HOME/vc/macprefs" ]; then
  chmod +x "$HOME/vc/macprefs/macprefs.sh" "$HOME/vc/macprefs/install-snapshot-agent.sh" 2>/dev/null || true
  echo "    macprefs ready. To restore this Mac's settings, run deliberately:"
  echo "      ~/vc/macprefs/macprefs.sh import ~/vc/macprefs-config/current --quit-apps"
  echo "    and then, to keep snapshots current:"
  echo "      ~/vc/macprefs/install-snapshot-agent.sh"
else
  echo "!! ~/vc/macprefs missing — no preference restore available" >&2
fi

# --- Stage 7: transport (optional) --------------------------------------
# Not part of the Mac. This publishes commits made locally — used by
# Claude sessions working in these clones, and by the macprefs snapshot
# agent to publish its snapshots. Skip it and everything above still
# works; you then push by hand.
if [ "$SKIP_TRANSPORT" -eq 1 ]; then
  echo "==> [7/7] Transport — skipped (--skip-transport)"
  echo "    Enable later with: ~/vc/git-autosync/install.sh"
else
  echo "==> [7/7] Transport (optional)"
  if [ -f "$HOME/vc/git-autosync/install.sh" ]; then
    "$HOME/vc/git-autosync/install.sh" || echo "!! git-autosync/install.sh reported errors — the agents may not be running" >&2
  else
    echo "!! ~/vc/git-autosync/install.sh missing — commits will not publish themselves" >&2
  fi
fi

# --- Manual steps -------------------------------------------------------
#
# Every stage above reports its own errors and lets the run continue, so
# that this closing checklist is always printed. The exit code, not the
# word "Done", is what says whether the run was clean.
if [ -n "$failed_clones" ]; then
  echo >&2
  echo "!! These repos were NOT cloned:$failed_clones" >&2
  echo "   Everything that reads them was skipped or ran incomplete." >&2
fi

cat <<'EOF'

==> Finished. Remaining manual steps (see setup-procedures.md, step A10):
  - Sign in: iCloud, OneDrive, WhatsApp (QR code), Chrome, Claude
  - Claude in Chrome extension: install from Chrome
  - Claude add-ins for Word/Excel: install from within Word/Excel
  - Claude Code in VS Code: log in with "Claude.ai Subscription"
  - Claude <-> GitHub connector: install AND authorize (two separate acts)
  - Logi Options+: reboot, then assign the MX Keys screenshot key
  - Maccy: launch at login, history size, hotkey
  - Control Center Toggle.app: built by stage 5 — launch it once, grant
    Accessibility, then bind a key to it in Shortcuts
  - Passwords app: syncs via Apple account automatically

==> Verify:
  git alias | wc -l                        # the full alias set, not 0
  git config user.email                    # from machine-config/gitconfig
  readlink ~/.config/git-autosync/repos    # -> ~/vc/machine-config/git-autosync-repos
  launchctl list | grep git-autosync       # two agents, if stage 7 ran
  ls ~/Library/Services                    # the Finder Quick Actions
EOF

if [ -n "$failed_clones" ]; then
  echo "==> Finished WITH ERRORS: could not clone$failed_clones" >&2
  exit 1
fi
