#!/bin/zsh
# bootstrap.sh — bootstrap a fresh Mac.
#
# Orchestration only: preconditions, clones into ~/vc, and calls into the
# other repositories' installers. A step that does real work inline belongs
# in a repository of its own; this file just calls it.
#
# Usage: bootstrap.sh [--dry-run]
#   --dry-run          print what would change instead of doing it; the
#                      checks still run, so it shows which stages would fire
#
# On a brand-new Mac, paste this into Terminal — three times, following
# what the script says at each stop (the README has the walkthrough):
#
#   curl -fsSL https://raw.githubusercontent.com/tiavelum/mac-bootstrap/main/bootstrap.sh -o $HOME/Downloads/bootstrap.sh && zsh $HOME/Downloads/bootstrap.sh
#
# Every problem is printed with a leading "!!"; none means a clean run.
# Safe to repeat: it skips what is already done.

set -e

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Everything that changes the machine goes through run(); reads do not.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] $*"
    return 0
  fi
  "$@"
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "==> Mac setup bootstrap — DRY RUN, nothing will be changed"
else
  echo "==> Mac setup bootstrap"
fi

# --- Stage 1: preconditions ---------------------------------------------
# gh is installed here, ahead of the clones: the app list that also names
# it lives in a private repo that cannot be cloned without it.

echo "==> [1/6] Preconditions"

# The Xcode tools install through a GUI dialog the script cannot wait out.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "    Xcode command line tools missing"
  run xcode-select --install
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] would stop here until the install finishes; continuing to show the rest"
  else
    echo "!! A macOS dialog has opened. Finish that install, then re-run this script." >&2
    exit 1
  fi
fi

# Homebrew's installer needs an administrator; say so up front rather than
# one stage in.
if ! groups 2>/dev/null | tr ' ' '\n' | grep -qx admin; then
  cat >&2 <<'EOF'
!! This user is not an administrator, and Homebrew cannot install without one.
   System Settings -> Users & Groups -> (i) next to this user ->
   "Allow this user to administer this computer" -> log out and in.
   Then paste the same line again.

EOF
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] would stop here; continuing to show the rest"
  else
    exit 1
  fi
fi

# Homebrew on this shell's PATH and, via .zprofile, on every future one —
# the installer only prints the instruction.
brew_env() {
  local line='eval "$(/opt/homebrew/bin/brew shellenv)"'
  eval "$(/opt/homebrew/bin/brew shellenv)"
  if ! grep -qsF 'brew shellenv' "$HOME/.zprofile"; then
    run sh -c "printf '\n# Homebrew (written by bootstrap.sh)\n%s\n' '$line' >> \"$HOME/.zprofile\""
  fi
}

# By path, not PATH: a Terminal opened before Homebrew existed does not have
# it, and re-running the installer over /opt/homebrew fails.
if [ ! -x /opt/homebrew/bin/brew ]; then
  # Ask for the password ourselves: NONINTERACTIVE stops the installer from
  # asking, and it would then fail as "need sudo access".
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] sudo -v   (would ask for your Mac password)"
  else
    echo "    Homebrew needs your Mac password:"
    sudo -v || { echo "!! could not get administrator access - is this an admin account?" >&2; exit 1; }
  fi
  echo "    installing Homebrew..."
  run env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ "$DRY_RUN" -eq 1 ] || brew_env
else
  echo "    Homebrew already installed"
  [ "$DRY_RUN" -eq 1 ] || brew_env
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "    installing gh..."
  run brew install gh
fi

if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
!! Not authenticated with GitHub. Every repo below is private.
   Run this, choosing GitHub.com / SSH / browser, then re-run this script:

     gh auth login -s admin:ssh_signing_key

   (The extra scope lets stage 3 register the SSH key for commit signing.)

   (If that says "command not found", open a new Terminal window first —
    this run has just put Homebrew on the PATH of future shells.)

EOF
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] would stop here; continuing to show the rest"
  else
    exit 1
  fi
fi

# --- Stage 2: clone -----------------------------------------------------
echo "==> [2/6] Cloning repos into ~/vc"
run mkdir -p "$HOME/vc"

# Pre-trust github.com's host key so the first clone does not stop to ask.
if ! grep -qs "github.com" "$HOME/.ssh/known_hosts" 2>/dev/null; then
  run mkdir -p "$HOME/.ssh"
  run sh -c "ssh-keyscan -t ed25519 github.com 2>/dev/null >> \"$HOME/.ssh/known_hosts\""
  echo "    github.com added to known_hosts"
fi

failed_clones=""
would_clone=""

clone_if_missing() {
  dest="$HOME/vc/$1"
  if [ -d "$dest/.git" ]; then
    echo "    $1 already cloned"
  elif run git clone --quiet "git@github.com:tiavelum/$1.git" "$dest"; then
    if [ "$DRY_RUN" -eq 1 ]; then would_clone="$would_clone $1"; else echo "    cloned $1"; fi
  else
    echo "!! could not clone $1" >&2
    failed_clones="$failed_clones $1"
  fi
}

# mac-config first: it carries the config every later stage reads.
clone_if_missing mac-config
# Tools that install or are invoked by later stages.
clone_if_missing mac-prefs                      # stage 6 needs the tool
clone_if_missing mac-prefs-config               # ... and its snapshots
clone_if_missing mac-quick-actions
# Knowledge, and in its claude/ folder the convention sessions follow.
clone_if_missing apple-setup
# This repository itself: on a new Mac the script ran from a download.
clone_if_missing mac-bootstrap

# have(): the file exists — or, in a dry run, would exist after stage 2.
have() {
  [ -f "$1" ] && return 0
  [ "$DRY_RUN" -eq 1 ] || return 1
  repo="${1#$HOME/vc/}"; repo="${repo%%/*}"
  case " $would_clone " in *" $repo "*) return 0 ;; esac
  return 1
}

# --- Stage 3: wire the config -------------------------------------------
echo "==> [3/6] Wiring config"

if have "$HOME/vc/mac-config/install.sh"; then
  run zsh "$HOME/vc/mac-config/install.sh" || echo "!! mac-config/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/mac-config/install.sh missing — git identity and aliases are NOT wired up" >&2
fi

# After install.sh: the script reads the signing key's path from the git
# config that install.sh has just wired.
if have "$HOME/vc/mac-config/register-signing-key.sh"; then
  run zsh "$HOME/vc/mac-config/register-signing-key.sh" \
    || echo "!! signing key not registered on GitHub — commits will not show as verified; see above" >&2
fi

# --- Stage 4: install what the config declares --------------------------
echo "==> [4/6] Apps and packages"

BREWFILE="$HOME/vc/mac-config/Brewfile"
if have "$BREWFILE"; then
  # brew bundle stops at the first failure; a second pass installs what a
  # flaky download skipped, and only what is still missing then is an error.
  if ! run brew bundle --file="$BREWFILE"; then
    echo "    brew bundle did not complete — retrying once for anything a flaky download skipped"
    run brew bundle --file="$BREWFILE" \
      || echo "!! brew bundle still reports errors — see the ✘ lines above; re-run later for those" >&2
  fi
  # A cask installed a moment ago is not on this shell's PATH yet.
  [ "$DRY_RUN" -eq 1 ] || eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "!! $BREWFILE missing — no apps installed" >&2
fi

# `code` reaches PATH only after VS Code is opened once; the binary in the
# bundle is there from the start.
CODE="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
command -v code >/dev/null 2>&1 && CODE="$(command -v code)"
EXTENSIONS="$HOME/vc/mac-config/vscode-extensions"
if have "$EXTENSIONS" && { [ -x "$CODE" ] || [ "$DRY_RUN" -eq 1 ]; }; then
  echo "    VS Code extensions"
  [ -f "$EXTENSIONS" ] || echo "    [dry-run] would install each id listed in $EXTENSIONS"
  [ -f "$EXTENSIONS" ] && sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$EXTENSIONS" | while IFS= read -r ext || [ -n "$ext" ]; do
    [ -n "$ext" ] || continue
    run "$CODE" --install-extension "$ext" --force
  done
elif have "$EXTENSIONS"; then
  echo "!! VS Code not found at $CODE — was the cask installed? Re-run after it is." >&2
fi

# Default applications last: they name apps that must exist, and duti comes
# from the Brewfile.
DEFAULTS="$HOME/vc/mac-config/apply-default-apps.sh"
if have "$DEFAULTS"; then
  run "$DEFAULTS" || echo "!! default applications not fully applied — see above" >&2
fi

# --- Stage 5: tools that install themselves -----------------------------
echo "==> [5/6] Tools"

if have "$HOME/vc/mac-quick-actions/install.sh"; then
  run "$HOME/vc/mac-quick-actions/install.sh" || echo "!! mac-quick-actions/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/mac-quick-actions/install.sh missing — Finder services not installed" >&2
fi

# --- Stage 6: preferences -----------------------------------------------
# After the apps exist. The import is printed, never run: it overwrites
# live settings, so it stays a deliberate command.
echo "==> [6/6] Preferences"

if have "$HOME/vc/mac-prefs/mac-prefs.sh"; then
  run chmod +x "$HOME/vc/mac-prefs/mac-prefs.sh" "$HOME/vc/mac-prefs/install-snapshot-agent.sh" || true
  echo "    mac-prefs ready. To restore this Mac's settings, run deliberately:"
  echo "      ~/vc/mac-prefs/mac-prefs.sh import ~/vc/mac-prefs-config/current --quit-apps"
  echo "    and then, to keep snapshots current:"
  echo "      ~/vc/mac-prefs/install-snapshot-agent.sh"
else
  echo "!! ~/vc/mac-prefs missing — no preference restore available" >&2
fi

# --- Closing ------------------------------------------------------------
# Every stage reports its own errors and continues, so this always prints;
# the exit code says whether the run was clean.
if [ -n "$failed_clones" ]; then
  echo >&2
  echo "!! These repos were NOT cloned:$failed_clones" >&2
  echo "   Everything that reads them was skipped or ran incomplete." >&2
fi

cat <<'EOF'

==> Finished. What this run leaves for you to do by hand:
  - Restore the saved preferences, deliberately (stage 6 only made it ready):
      ~/vc/mac-prefs/mac-prefs.sh import ~/vc/mac-prefs-config/current --quit-apps
    then keep them current:  ~/vc/mac-prefs/install-snapshot-agent.sh
  - Control Center Toggle.app (built by stage 5): launch it once, grant
    Accessibility, then bind a key to it in Shortcuts
  - Sign in to the apps that were installed, and grant what they ask for

==> Verify:
  git alias | wc -l                        # the full alias set, not 0
  git config user.email                    # from mac-config/gitconfig
  ls ~/Library/Services                    # the Finder Quick Actions
EOF

if [ -n "$failed_clones" ]; then
  echo "==> Finished WITH ERRORS: could not clone$failed_clones" >&2
  exit 1
fi

[ "$DRY_RUN" -eq 1 ] && echo "==> DRY RUN complete — nothing was changed."
exit 0
