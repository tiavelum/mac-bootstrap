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
# Claude sessions working in these clones, and the mac-prefs snapshot
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
# A new Mac has no git and no GitHub login, so this file cannot be cloned —
# but the repository is public and every Mac has curl. Open Terminal and
# paste this one line ($HOME means ~ and is on every keyboard):
#
#     curl -fsSL https://raw.githubusercontent.com/tiavelum/mac-bootstrap/main/bootstrap.sh -o $HOME/Downloads/bootstrap.sh && zsh $HOME/Downloads/bootstrap.sh
#
# It fetches the current script into Downloads and runs it. You will paste
# that same line THREE times; because it fetches every time, each run is
# the latest version, so a fix pushed between runs is picked up. The script
# stops twice for things only a person can do, tells you what, and picks up
# where it left off. Expected sequence:
#
#   before   → the account you are in must be an administrator (a new Mac's
#              first account always is). If not, the script says so and stops.
#
#   1st run  → stops at once: "Xcode command line tools missing".
#              A macOS dialog opens. Click Install, accept the licence,
#              wait for the download (a few minutes). Paste the line again.
#
#   2nd run  → asks for your Mac password once (Homebrew needs it), installs
#              Homebrew and gh,
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
#              every app in the Brewfile. Ends with "Finished", the few
#              things left for a person, and a verify block.
#
# Every problem the script sees is printed with a leading "!!". If you see
# none, the run was clean. If you see some, read them — they say what to
# do — and paste the line once more; the script is safe to repeat.
#
# Try it without changing anything: append --dry-run to the line, i.e.
#     ... && zsh $HOME/Downloads/bootstrap.sh --dry-run

set -e

SKIP_TRANSPORT=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --skip-transport) SKIP_TRANSPORT=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help) sed -n '2,71p' "$0"; exit 0 ;;
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

# The user must be an administrator: Homebrew's installer needs sudo to
# create /opt/homebrew, and it fails one stage in, in its own words, if not.
# A fresh Mac's first account is always an admin, so a real rebuild never
# sees this - but a second account, or a VM whose setup wizard was clicked
# through fast, can be a standard user. Found on the second VM run.
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

# Homebrew's installer needs sudo. Ask for the password here, once, where a
# person expects it - and cache it - rather than letting the installer ask.
# Setting NONINTERACTIVE for the installer (to skip its "press RETURN")
# also stops it asking for the password, and it then fails as "need sudo
# access" even for an administrator. Found on the second VM run.
if ! sudo -n true 2>/dev/null; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    [dry-run] sudo -v   (would ask for your Mac password once)"
  else
    echo "    Homebrew needs your Mac password once:"
    sudo -v || { echo "!! could not get administrator access - is this an admin account?" >&2; exit 1; }
  fi
fi
# "Once" has to be made true: sudo forgets the password after five minutes
# and the app downloads in stage 4 take longer, so casks with privileged
# installers (OneDrive, Logi Options+) asked again mid-run - the third VM run
# showed four prompts. Refresh the credential every minute in the background
# for as long as this script lives; the loop ends by itself when it is gone.
if [ "$DRY_RUN" -eq 0 ]; then
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT
fi

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
  # NONINTERACTIVE skips the "press RETURN to continue" prompt. It also stops
  # the installer asking for a password - which is why sudo was cached above.
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

# mac-config first: it carries the config every later stage reads.
clone_if_missing mac-config
# Tools that install or are invoked by later stages.
clone_if_missing mac-prefs                      # stage 6 needs the tool
clone_if_missing mac-prefs-config               # ... and its snapshots
clone_if_missing mac-quick-actions
# Knowledge, and in its claude/ folder the convention sessions follow.
clone_if_missing apple-setup
# Transport for stage 7; cloned here so the repo list is complete either way.
clone_if_missing git-autosync
# This repository itself. On a brand-new Mac this script is run from a
# curl download in ~/Downloads, so nothing has cloned it yet — and the sync list names
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

if have "$HOME/vc/mac-config/install.sh"; then
  run zsh "$HOME/vc/mac-config/install.sh" || echo "!! mac-config/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/mac-config/install.sh missing — git identity, aliases and the" >&2
  echo "   autosync repo list are NOT wired up" >&2
fi

# --- Stage 4: install what the config declares --------------------------
echo "==> [4/7] Apps and packages"

BREWFILE="$HOME/vc/mac-config/Brewfile"
if have "$BREWFILE"; then
  # brew bundle stops at the first failure by default, so one server having
  # a bad minute (WhatsApp's returned a 500 on the first real run) left
  # everything after it uninstalled — and the steps that depend on those
  # tools then failed too. The retry loop below is what matters: a second
  # pass installs whatever the first one skipped, and only what is still
  # missing after that counts as an error. (No extra flags: the third VM
  # run showed that a flag brew does not know aborts the whole bundle.)
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

# `code` is not on PATH until VS Code itself installs its shell command,
# which needs the app opened once. The binary is inside the bundle from the
# moment the cask lands, so use that path and skip the chicken-and-egg.
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

# Default applications, last in this stage: the bindings name applications
# that must already exist, and duti itself comes from the Brewfile above.
DEFAULTS="$HOME/vc/mac-config/apply-default-apps.sh"
if have "$DEFAULTS"; then
  run "$DEFAULTS" || echo "!! default applications not fully applied — see above" >&2
fi

# --- Stage 5: tools that install themselves -----------------------------
echo "==> [5/7] Tools"

# Installs the Finder services and builds Control Center Toggle.app, the
# application that holds the Accessibility grant for the Control Center
# hotkey. Granting that permission and binding the key stay manual.
if have "$HOME/vc/mac-quick-actions/install.sh"; then
  run "$HOME/vc/mac-quick-actions/install.sh" || echo "!! mac-quick-actions/install.sh reported errors — see above" >&2
else
  echo "!! ~/vc/mac-quick-actions/install.sh missing — Finder services not installed" >&2
fi

# --- Stage 6: preferences -----------------------------------------------
# Must come after the apps exist: restoring a preference domain for an app
# that is not installed writes a plist nothing will read.
#
# The restore itself is NOT run automatically. It overwrites live settings
# on a machine you may already have configured, so it stays a deliberate,
# explicit command.
echo "==> [6/7] Preferences"

if have "$HOME/vc/mac-prefs/mac-prefs.sh"; then
  run chmod +x "$HOME/vc/mac-prefs/mac-prefs.sh" "$HOME/vc/mac-prefs/install-snapshot-agent.sh" || true
  echo "    mac-prefs ready. To restore this Mac's settings, run deliberately:"
  echo "      ~/vc/mac-prefs/mac-prefs.sh import ~/vc/mac-prefs-config/current --quit-apps"
  echo "    and then, to keep snapshots current:"
  echo "      ~/vc/mac-prefs/install-snapshot-agent.sh"
else
  echo "!! ~/vc/mac-prefs missing — no preference restore available" >&2
fi

# --- Stage 7: transport (optional) --------------------------------------
# Not part of the Mac. This publishes commits made locally — used by
# Claude sessions working in these clones, and by the mac-prefs snapshot
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
  readlink ~/.config/git-autosync/repos    # -> ~/vc/mac-config/git-autosync-repos
  launchctl list | grep git-autosync       # two agents, if stage 7 ran
  ls ~/Library/Services                    # the Finder Quick Actions
EOF

if [ -n "$failed_clones" ]; then
  echo "==> Finished WITH ERRORS: could not clone$failed_clones" >&2
  exit 1
fi

[ "$DRY_RUN" -eq 1 ] && echo "==> DRY RUN complete — nothing was changed."
exit 0
