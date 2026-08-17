# mac-bootstrap

Bootstrap for a fresh MacBook Air. **Orchestration only** — this repo owns
no configuration and no mechanisms of its own.

## Run it on a brand-new Mac

A fresh machine has no `git` and no GitHub login, so this repo cannot be
cloned yet — and every repo the script needs is private. The way in is the
browser: open this repo on GitHub → `bootstrap.sh` → **Raw** → save it to
Downloads. Then in Terminal, paste exactly:

```zsh
zsh $HOME/Downloads/bootstrap.sh
```

(`$HOME` is the same as `~`, and it is on every keyboard.) Stage 1 installs
the Xcode command-line tools, Homebrew and `gh`, then stops and tells you to
run `gh auth login` — choose SSH and the browser flow. Paste the same line
again and it runs through all seven stages; the copy of this repo it clones
into `~/vc` is the one you keep.

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

A macOS virtual machine is the cheapest fresh machine. On Apple Silicon:

```zsh
brew install --cask utm
```

UTM → **Create a New Virtual Machine → Virtualize → macOS 12+** downloads
Apple's own recovery image and installs a clean guest. Give it 60 GB and
half your RAM; the first boot walks the normal macOS setup. Then, inside the
guest, sign in to iCloud only if you want to test that path — otherwise skip
it — open Terminal and run the block under **Run it** above. `gh auth login`
inside the guest is a real login: use the browser flow, or paste a token you
revoke afterwards.

When it breaks, read the output, fix the script here, and re-run in the guest —
or delete the guest and start clean. Snapshot the guest right after the OS
install so "start clean" costs seconds.

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
2  clone              the other repos into ~/vc, machine-config first
3  wire the config    calls machine-config/install.sh (identity, aliases, sync list)
4  apps & extensions  brew bundle from the Brewfile, VS Code extensions
5  tools              repos that install themselves, each via its own install.sh
6  preferences        makes macprefs executable and prints its commands —
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

The list of apps to install lives in the private `machine-config` repo, and `gh` is
on that list — but `machine-config` cannot be cloned without an authenticated `gh`.
The loop is broken by installing `gh` **directly in stage 1, ahead of every
clone**; it stays in the Brewfile for completeness, where it is a no-op on a
machine that already has it. Authentication itself no script can do, so an
unauthenticated `gh` stops the run and names the command to type.

## Repositories

The authoritative map of which repo holds what is in
[setup-design.md](https://github.com/tiavelum/setup-docs/blob/main/setup-design.md).

## `install-log.md`

Chronological journal of what was installed and when. Append-only: entries are
correct *as history*, so stale paths in old rows stay. Current truth lives in
`setup-docs`.

## Workflow

1. Install something → add a row to `install-log.md`
2. If it's Homebrew-installable → also add it to `machine-config/Brewfile`
3. Commit — nothing commits for you; git-autosync only transports commits
4. `touch .git/autosync-push` to publish, then check `.git/autosync-status`
