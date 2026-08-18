# mac-bootstrap

Bootstrap for a fresh MacBook Air. **Orchestration only** — this repo owns
no configuration and no mechanisms of its own.

## Run it on a brand-new Mac — the walkthrough

You will paste one line three times. The script stops twice, for the two
things no script can do — accept Apple's licence for the developer tools,
and prove to GitHub that you are you — and continues from where it stopped.
Everything else is automatic. Budget 20–40 minutes, most of it downloads.

**Before you start.** A fresh Mac has no `git` and no GitHub login, so this
repository cannot be cloned yet. Open Safari → `github.com/tiavelum/mac-bootstrap`
→ `bootstrap.sh` → **Raw** → save it to Downloads. Then open Terminal
(Spotlight → "Terminal") and paste:

```zsh
zsh $HOME/Downloads/bootstrap.sh
```

`$HOME` means `~` and is on every keyboard.

**Before run 1 — be an administrator.** The account you run this from must be
able to administer the computer; Homebrew needs `sudo`. A new Mac's first
account always is. A second account, or a VM whose setup was clicked through
quickly, may not be — the script checks and says so before doing anything.
System Settings → Users & Groups → ⓘ next to the user → *Allow this user to
administer this computer*, then log out and in.

**Run 1 — the developer tools.** The script stops immediately:
`Xcode command line tools missing`. A macOS dialog opens (if you cannot see
it, it is behind the Terminal window). Click **Install**, accept the licence,
wait — it is a couple of gigabytes. When it says done, paste the same line
again.

**Run 2 — Homebrew, gh, and your login.** The script asks for your Mac
password once — Homebrew needs it — then installs Homebrew and `gh` with no
further questions, then
stops: `Not authenticated with GitHub`. In the **same** Terminal window,
type:

```zsh
gh auth login
```

Answer the prompts: **GitHub.com** → **SSH** → **Yes**, generate a new key
→ passphrase: on a real Mac give one (it is stored in the keychain, you type
it once); on a throwaway VM leave it empty → title: just press Enter →
**Login with a web browser**.

It then prints an eight-character code — `XXXX-XXXX` — and says *press
Enter to open github.com in your browser*. **Write the code down before you
press Enter.** Safari opens on top of the Terminal and the code stays behind
it. Type the code into the GitHub page, click Authorize, and when it says
"Congratulations, you're all set", go back to Terminal and paste the script
line a third time.

**Run 3 — everything else.** All seven stages, unattended: seven repositories
cloned into `~/vc`, git identity and aliases wired, every app in the Brewfile
installed, Finder actions and the hotkey app built, preferences readied,
sync agents loaded. It ends with `==> Finished`, a list of the sign-ins that
remain, and a short verify block.

**Reading the result.** Every problem the script sees is printed with a
leading `!!`. No `!!` anywhere means the run was clean. If there are some,
each says what to do; fix it and paste the line once more — the script is
safe to repeat, it skips what is already done. A `✘` from `brew bundle` is
usually a download that failed on the vendor's side; the script retries once
and, if it still fails, names it so you can `brew install` it later.

**After it finishes — the manual steps.** These need a person and a screen,
in this order: sign in to iCloud; open the Passwords app so it syncs; open
VS Code once and sign in to Claude Code; launch `Control Center Toggle.app`
once, grant Accessibility when asked, then bind a key to it in Shortcuts;
reboot before assigning the MX Keys screenshot key in Logi Options+; then
the app sign-ins (Chrome, WhatsApp by QR code, OneDrive, Claude). Preference
import is deliberate and never automatic:
`~/vc/mac-prefs/mac-prefs.sh import ~/vc/mac-prefs-config/current --quit-apps`.
The full list with detail is procedures A10 in `apple-setup/docs`.

## Run it again later

```zsh
cd $HOME/vc/mac-bootstrap && ./bootstrap.sh     # --skip-transport to leave stage 7 out
```

Idempotent — re-running is how you repair a machine whose wiring drifted.

## Try it first: `--dry-run`

```zsh
./bootstrap.sh --dry-run
```

Prints every command that would change the machine instead of running it, and
changes nothing — safe on a Mac you care about. The checks still run for real,
so the output shows which stages *would* fire on this machine and which are
already satisfied. On an empty machine it narrates all seven stages; on a
finished one it says "already" at each.

What it cannot tell you: whether the commands *succeed*. For that there is
only one honest test, and it is not this Mac.

## Test it for real: a throwaway machine

The script has to be exercised on a machine that starts from nothing — that is
the only run that tests what it exists for, and the only one that can go wrong
without costing anything. **Never test it on your working Mac**: it would
tell you almost nothing (everything is already there) and it can still change
things (rebuild the hotkey app, upgrade casks).

A macOS virtual machine is the cheapest fresh machine. UTM is in the
Brewfile, so a bootstrapped Mac already has it; otherwise
`brew install --cask utm`.

**Create the guest.** UTM → **Create a New Virtual Machine → Virtualize →
macOS 12+**. It downloads Apple's own recovery image and installs a clean
guest. Give it 60 GB and half your RAM. **Leave sharing off** — no shared
folder, no shared clipboard: a guest that can see your `~/vc` is not a bare
machine, and the test is worthless. First boot walks the normal macOS
setup; make a local user, skip iCloud.

**Snapshot it before you type anything.** Stop the guest, then in UTM's
sidebar right-click it → snapshot, name it `clean`. That is the reset
button, and it is the step that gets skipped: without it, "start over"
means reinstalling macOS, which is an hour, not a minute. Do it now.

**Run the walkthrough** at the top of this file inside the guest — browser,
Raw, Downloads, three pastes. `gh auth login` in the guest is a real login
to your real account: browser flow, empty passphrase is fine.

**When it breaks:** read the `!!` lines, fix the script here, push, restore
`clean`, run again. That loop is what the snapshot buys.

**When to test again:** whenever `bootstrap.sh`, the Brewfile, or one of the
installers it calls has changed since the last clean run. A script that
changed is untested again, however small the change looked.

**When you are done, revoke what the guest was given.** `gh auth login` in the
guest uploaded an SSH key to your GitHub account and authorised a device;
deleting the VM does not undo either. Remove the key at github.com →
Settings → SSH and GPG keys (titled "GitHub CLI", dated the day you tested)
and, to be thorough, the device under Settings → Applications → Authorized
GitHub Apps → GitHub CLI. Also note that stage 7 makes the guest's sync
agents live with your credentials: harmless while it has nothing to commit,
but a reason not to leave a test guest running for weeks.

**What the first real run taught** (2026-08-17, from a bare guest): the
script reached all seven stages and its errors were all visible, which is
what mattered. Six things were wrong, all fixed the same day: Homebrew's
installer prompted for Return (now `NONINTERACTIVE`); Homebrew was on the
script's PATH but not the user's, so the very next command after "run
`gh auth login`" was *command not found* (now written to `~/.zprofile`);
first SSH contact with github.com stopped mid-clone to ask for trust (now
pre-trusted); a single flaky download aborted the whole `brew bundle` (now
retried once); `code` was looked up on PATH before VS Code had put it there
(now called inside the app bundle); and this repository itself was never
cloned. Fifteen minutes of running found what three careful readings had not.

Cheaper still, for the per-user stages only, is a fresh user account on this
Mac (System Settings → Users & Groups). Everything from stage 2 onward is
per-user, so it is a good imitation of a fresh machine — but it shares
Homebrew and the Xcode tools with your account, so it does not test stage 1.

## The seven stages

```
1  preconditions      Homebrew, gh, gh auth status — unauthenticated stops the run
2  clone              the other repos into ~/vc, mac-config first
3  wire the config    calls mac-config/install.sh (identity, aliases, sync list)
4  apps & extensions  brew bundle from the Brewfile, VS Code extensions
5  tools              repos that install themselves, each via its own install.sh
6  preferences        makes mac-prefs executable and prints its commands —
                      the restore itself stays a deliberate manual command
7  transport          optional: git-autosync. Skip with --skip-transport
```

## The invariant

`bootstrap.sh` contains **only preconditions, clones and calls**. If a step
needs real work inline, it belongs in a repo of its own with its own
`install.sh`, and this file just calls it. That rule is what keeps this repo
from slowly becoming the place where everything lands.

Check it whenever you touch the file: open it and look for a step doing domain
work. There should not be one.

## The deliberate circular dependency

The list of apps to install lives in the private `mac-config` repo, and `gh` is
on that list — but `mac-config` cannot be cloned without an authenticated `gh`.
The loop is broken by installing `gh` **directly in stage 1, ahead of every
clone**; it stays in the Brewfile for completeness, where it is a no-op on a
machine that already has it. Authentication itself no script can do, so an
unauthenticated `gh` stops the run and names the command to type.

## Repositories

The authoritative map of which repo holds what is in
[setup-design.md](https://github.com/tiavelum/apple-setup/blob/main/docs/setup-design.md).

## `install-log.md`

Chronological journal of what was installed and when. Append-only: entries are
correct *as history*, so stale paths in old rows stay. Current truth lives in
`apple-setup`.

## Workflow

1. Install something → add a row to `install-log.md`
2. If it's Homebrew-installable → also add it to `mac-config/Brewfile`
3. Commit — nothing commits for you; git-autosync only transports commits
4. `touch .git/autosync-push` to publish, then check `.git/autosync-status`
