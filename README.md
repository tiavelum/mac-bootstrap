# mac-setup

Bootstrap for a fresh MacBook Air. **Orchestration only** — this repo owns
no configuration and no mechanisms of its own.

## Run it

```zsh
# Homebrew and gh come first — every repo here is private
brew install gh && gh auth login          # choose SSH
git clone git@github.com:tiavelum/mac-setup.git ~/vc/mac-setup
cd ~/vc/mac-setup && ./bootstrap.sh        # --skip-transport to leave stage 7 out
```

`bootstrap.sh` is the entry point. It installs Homebrew and `gh` itself if they
are missing, and stops with instructions if you are not authenticated.

## The seven stages

```
1  preconditions      Homebrew, gh, gh auth status — unauthenticated stops the run
2  clone              the other repos into ~/vc, dotfiles first
3  wire the config    calls dotfiles/install.sh (identity, aliases, sync list)
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

The list of apps to install lives in the private `dotfiles` repo, and `gh` is
on that list — but `dotfiles` cannot be cloned without an authenticated `gh`.
The loop is broken by installing `gh` **directly in stage 1, ahead of every
clone**; it stays in the Brewfile for completeness, where it is a no-op on a
machine that already has it. Authentication itself no script can do, so an
unauthenticated `gh` stops the run and names the command to type.

## Repositories

The authoritative map of which repo holds what is in
[setup-design.md](https://github.com/tiavelum/setup-docs/blob/main/setup-design.md).

## `mac-setup-log.md`

Chronological journal of what was installed and when. Append-only: entries are
correct *as history*, so stale paths in old rows stay. Current truth lives in
`setup-docs`.

## Workflow

1. Install something → add a row to `mac-setup-log.md`
2. If it's Homebrew-installable → also add it to `dotfiles/Brewfile`
3. Commit — nothing commits for you; git-autosync only transports commits
4. `touch .git/autosync-push` to publish, then check `.git/autosync-status`
