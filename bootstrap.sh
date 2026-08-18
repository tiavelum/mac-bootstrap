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
# Usage: ./bootstrap.sh [--dry-run] [--skip-transport]
#
#   --dry-run   print every command that would change the machine instead of
#               running it. Checks still run for real, so the output shows
#               which stages *would* fire on this machine and which are
#               already satisfied. Safe on a Mac you care about.
#
# ══════════════════════════════════════════════════════════════════════════
# RUNNING THIS ON A BRAND-NEW MAC — the whole procedure, nothing else needed
# ══════════════════════════════════════════════════════════════════════════
#
# A new Mac has no git and no GitHub login, so this file cannot be cloned.
# Get it through the browser: github.com/tiavelum/mac-bootstrap →
# bootstrap.sh → "Raw" → save to Downloads. Then open Terminal and paste
# this ($HOME means ~ and is on every keyboard):
#
#     zsh $HOME/Downloads/bootstrap.sh
#
# You will paste that same line THREE times. The script stops twice for
# things only a person can do, tells you what, and picks up where it left
# off. Expected sequence:
#
#   1st run  → stops at once: "Xcode command line tools missing".
#              A macOS dialog opens. Click Install, accept the licence,
#              wait for the download (a few minutes). Paste the line again.
#
#   2nd run  → installs Homebrew (asks for your Mac password once) and gh,
#              then stops: "Not authenticated with GitHub". In the SAME
#              window, type:
#
#                  gh auth login
#
#              Answer: GitHub.com → SSH → Yes, generate a key → (passphrase
#              optional; on a real Mac give one, it is stored in the
#              keychain) → title: press Enter → Login with a web browser.
#              It shows an 8-character CODE like XXXX-XXXX and says press
#              Enter to open the browser. WRITE THE CODE DOWN FIRST — Safari
#              opens on top of this window and the code stays behind it.
#              Type the code into GitHub, Authorize, come back to Terminal.
#              Paste the line a third time.
#
#   3rd run  → runs all seven stages unattended. Takes a while: it downloads
#              every app in the Brewfile. Ends with "Finished", a list of
#              the manual sign-ins that remain, and a verify block.
#
# Every problem the script sees is printed with a leading "!!". If you see
# none, the run was clean. If you see some, read them — they say what to
# do — and paste the line once more; the script is safe to repeat.
#
# Try it without changing anything:   zsh $HOME/Downloads/bootstrap.sh --dry-run

set -e

SKIP_TRANSPORT=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --skip-transport) SKIP_TRANSPORT=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help) sed -n '2,66p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# run: execute a command, or in a dry run print it and pretend it succeeded.
# Everything that changes the machine goes through this; the checks that
# only read state do not, so a dry run still reflects the real machine.
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
  run xcode-select --install
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] would stop here until the install finishes; continuing to show the rest"
  else
    echo "!! A macOS dialog has opened. Finish that install, then re-run this script." >&2
    exit 1
  fi
fi

# brew_env: put Homebrew on this shell's PATH, and on every future shell's.
# Two things went wrong on the first real run without this: Homebrew's own
# installer prints "add this to your .zprofile" and the script ignored it,
# so the moment the script exited, gh (and later code) were "not found" in
# the very shell the user was left in. And it exited to ask for a login,
# so that was the first thing they typed.
brew_env() {
  local line='eval "$(/opt/homebrew/bin/brew shellenv)"'
  eval "$(/opt/homebrew/bin/brew shellenv)"
  if ! grep -qsF 'brew shellenv' "$HOME/.zprofile"; then
    run sh -c "printf '\n# Homebrew (written by bootstrap.sh)\n%s\n' '$line' >> \"$HOME/.zprofile\""
  fi
}

if ! command -v brew >/dev/null 2>&1; then
  echo "    installing Homebrew..."
  # NONINTERACTIVE: skip the "press RETURN to continue" prompt. It has no
  # decision behind it, and it turned an unattended stage into a babysat one.
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

     gh auth login

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
echo "==> [2/7] Cloning repos into ~/vc"
run mkdir -p "$HOME/vc"

# First contact with github.com over SSH asks "are you sure you want to
# continue connecting?" — once per machine, and always in the middle of a
# fresh bootstrap. Trust GitHub's published host key up front instead.
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

# machine-config first: it carries the config every later stage reads.
clone_if_missing machine-config
# Tools that install or are invoked by later stages.
clone_if_missing macprefs                      # stage 6 needs the tool
clone_if_missing macprefs-config               # ... and its snapshots
clone_if_missing macos-quick-actions
# Knowledge, and in its claude/ folder the convention sessions follow.
clone_if_missing apple-setup
# Transport for stage 7; cloned here so the repo list is complete either way.
clone_if_missing git-autosync
# This repository itself. On a brand-new Mac this script is run from a
# browser download, so nothing has cloned it yet — and the sync list names
# it, so the transport would otherwise warn about it forever.
clone_if_missing mac-bootstrap

# have: true if the file exists — or, in a dry run, if it lives in a repo
# that the dry run would have cloned. Lets the later stages describe what
# they would do on a fresh machine instead of reporting everything missing.
have() {
  [ -f "$1" ] && return 0
  [ "$DRY_RUN" -eq 1 ] || return 1
  repo="${1#$HOME/vc/}"; repo="${repo%%/*}"
  case " $would_clone " in *" $repo "*) return 0 ;; esac
  return 1
}

# --- Stage 3: wire the config -------------------------------------------
# Each repo installs itself; this script only calls.
echo "==> [3/7] Wiring config"

if have "$HOME/vc/machine-config/install.sh"; then
  run zsh "$HOME/vc/machine-config/install.sh" || echo "!! machine-config/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/machine-config/install.sh missing — git identity, aliases and the" >&2
  echo "   autosync repo list are NOT wired up" >&2
fi

# --- Stage 4: install what the config declares --------------------------
echo "==> [4/7] Apps and packages"

BREWFILE="$HOME/vc/machine-config/Brewfile"
if have "$BREWFILE"; then
  # brew bundle stops at the first failure by default, so one server having
  # a bad minute (WhatsApp's returned a 500 on the first real run) left
  # everything after it uninstalled — and the steps that depend on those
  # tools then failed too. --no-lock is harmless; the retry loop below is
  # what matters: a second pass installs whatever the first one skipped,
  # and only what is still missing after that counts as an error.
  if ! run brew bundle --file="$BREWFILE" --no-lock; then
    echo "    brew bundle did not complete — retrying once for anything a flaky download skipped"
    run brew bundle --file="$BREWFILE" --no-lock \
      || echo "!! brew bundle still reports errors — see the ✘ lines above; re-run later for those" >&2
  fi
  # A cask installed a moment ago is not on this shell's PATH yet.
  [ "$DRY_RUN" -eq 1 ] || eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "!! $BREWFILE missing — no apps installed" >&2
fi

# `code` is not on PATH until VS Code itself installs its shell command,
# which needs the app opened once. The binary is inside the bundle from the
# moment the cask lands, so use that path and skip the chicken-and-egg.
CODE="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
command -v code >/dev/null 2>&1 && CODE="$(command -v code)"
EXTENSIONS="$HOME/vc/machine-config/vscode-extensions"
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

# Default applications, last in this stage: the bindings name applications
# that must already exist, and duti itself comes from the Brewfile above.
DEFAULTS="$HOME/vc/machine-config/apply-default-apps.sh"
if have "$DEFAULTS"; then
  run "$DEFAULTS" || echo "!! default applications not fully applied — see above" >&2
fi

# --- Stage 5: tools that install themselves -----------------------------
echo "==> [5/7] Tools"

# Installs the Finder services and builds Control Center Toggle.app, the
# application that holds the Accessibility grant for the Control Center
# hotkey. Granting that permission and binding the key stay manual.
if have "$HOME/vc/macos-quick-actions/install.sh"; then
  run "$HOME/vc/macos-quick-actions/install.sh" || echo "!! macos-quick-actions/install.sh reported errors — see above" >&2
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

if have "$HOME/vc/macprefs/macprefs.sh"; then
  run chmod +x "$HOME/vc/macprefs/macprefs.sh" "$HOME/vc/macprefs/install-snapshot-agent.sh" || true
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
  if have "$HOME/vc/git-autosync/install.sh"; then
    run "$HOME/vc/git-autosync/install.sh" || echo "!! git-autosync/install.sh reported errors — the agents may not be running" >&2
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

==> Finished. Remaining manual steps (see apple-setup/docs/setup-procedures.md, step A10):
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

[ "$DRY_RUN" -eq 1 ] && echo "==> DRY RUN complete — nothing was changed."
exit 0
