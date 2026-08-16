# mac-setup

Personal log and automation for setting up my MacBook Air. **Scripts and
log only** — personal configuration lives in
[dotfiles](https://github.com/tiavelum/dotfiles).

- **`mac-setup-log.md`** — chronological log of everything installed/configured
- **`Brewfile`** — apps installable via Homebrew (`brew bundle`)
- **`install.sh`** — bootstrap for a fresh Mac: Homebrew, apps, VS Code
  extensions, then clones `dotfiles` + `git-autosync` into `~/vc` and wires
  them up

## Related repos

| Repo | Holds | Kind |
|---|---|---|
| `dotfiles` | git aliases, git-autosync repo list | config (private) |
| `git-autosync` | the clone↔GitHub sync tool | script (public) |
| `macprefs` / `macprefs-config` | macOS preference snapshots | script / config |

The split is deliberate: a script is generic and shareable, a config is
personal and machine-facing. `install.sh` therefore *points at* config it
does not own — `gitconfig-aliases` used to live here and was moved out on
2026-08-16.

## Fresh Mac

```zsh
gh auth login                    # SSH — needed before the private clones
git clone git@github.com:tiavelum/mac-setup.git ~/vc/mac-setup
cd ~/vc/mac-setup
./install.sh
```

(First `chmod +x install.sh` if needed.)

Then clone the rest of the repos named in
`~/vc/dotfiles/git-autosync-repos` — that list doubles as the inventory of
what a complete machine has.

## Workflow

1. Install something → add a row to `mac-setup-log.md`
2. If it's Homebrew-installable → also add it to `Brewfile`
3. Commit — nothing commits for you; git-autosync only transports commits
4. `touch .git/autosync-push` to publish, then check `.git/autosync-status`
