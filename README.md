# mac-setup

Personal log and automation for setting up my MacBook Air.

- **`mac-setup-log.md`** — chronological log of everything installed/configured
- **`Brewfile`** — apps installable via Homebrew (`brew bundle`)
- **`install.sh`** — bootstrap script for a fresh Mac (installs Homebrew, apps, VS Code extensions; lists remaining manual steps)

## Fresh Mac in three commands

```zsh
git clone https://github.com/tiavelum/mac-setup.git ~/vc/mac-setup
cd ~/vc/mac-setup
./install.sh
```

(First `chmod +x install.sh` if needed.)

## Workflow

1. Install something → add a row to `mac-setup-log.md`
2. If it's Homebrew-installable → also add it to `Brewfile`
3. Commit and push
