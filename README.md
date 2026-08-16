# mac-setup

Bootstrap for a fresh MacBook Air. **Orchestration only** — this repo owns
no configuration and no mechanisms of its own.

- **`install.sh`** — preconditions (Homebrew, authenticated `gh`), clones
  the other repos into `~/vc`, runs each one's installer, installs what
  `dotfiles` declares
- **`mac-setup-log.md`** — chronological journal of what was installed and
  when. Append-only: entries are correct *as history*, so stale paths in
  old rows stay. Current truth lives in `setup-docs`

## The invariant

`install.sh` contains **only preconditions, clones and calls**. If a step
needs real work inline, it belongs in a repo of its own with its own
`install.sh`, and this file just calls it. That rule is what keeps this
repo from slowly becoming the place where everything lands — see
[setup-13](https://github.com/tiavelum/setup-docs/blob/main/setup-13-repo-architecture.md).

Check it whenever you touch the file: open it and look for a step doing
domain work. There should not be one.

## Repo map

| Repo | Holds |
|---|---|
| [dotfiles](https://github.com/tiavelum/dotfiles) | `gitconfig`, `Brewfile`, `vscode-extensions`, `git-autosync-repos` + its own `install.sh` |
| [git-autosync](https://github.com/tiavelum/git-autosync) | clone ↔ GitHub sync tool (public) |
| [macprefs](https://github.com/tiavelum/macprefs) / `macprefs-config` | macOS preference export/import / generated snapshots |
| [macos-quick-actions](https://github.com/tiavelum/macos-quick-actions) | Finder services (installer still open) |
| [setup-docs](https://github.com/tiavelum/setup-docs) | the knowledge: why, pitfalls, open items |

## Fresh Mac

```zsh
# Homebrew and gh come first — every repo here is private
brew install gh && gh auth login          # choose SSH
git clone git@github.com:tiavelum/mac-setup.git ~/vc/mac-setup
cd ~/vc/mac-setup && ./install.sh
```

`install.sh` installs Homebrew and `gh` itself if they are missing, and
stops with instructions if you are not authenticated.

## Workflow

1. Install something → add a row to `mac-setup-log.md`
2. If it's Homebrew-installable → also add it to `dotfiles/Brewfile`
3. Commit — nothing commits for you; git-autosync only transports commits
4. `touch .git/autosync-push` to publish, then check `.git/autosync-status`
