# Mac Setup Log

Chronological log of everything installed and configured on this MacBook Air.
Goal: document the setup so it can be automated later (see `Brewfile` and `install.sh`).

> Note: logging started late, so early entries are reconstructed from memory and dates are approximate.

---

## 2026 — early (approximate)

| Item | Type | Notes |
|---|---|---|
| WhatsApp | App | |
| Passwords app keywords | Config | One-time setup; synced via Apple account, no need to repeat |
| OneDrive | App | |

## 2026-07 — mid July

| Item | Type | Notes |
|---|---|---|
| Google Photos → Apple Photos transfer tools | One-off | Migration done; code and docs at <https://github.com/tiavelum/google-photos-to-icloud> |

## 2026-07-26

| Item | Type | Notes |
|---|---|---|
| Google Chrome | App | |
| Claude in Chrome extension | Extension | Installed from Chrome |
| Claude extension for Word | Office add-in | Installed inside Word |
| Claude extension for Excel | Office add-in | Installed inside Excel |
| Claude Code extension for VS Code | VS Code extension | Login choice: **Claude.ai Subscription** (included in Claude plan, not API/Console billing) |
| GitHub personal access token (classic) | Config | For git over HTTPS in Terminal; `repo` scope; stored silently in macOS Keychain (not the Passwords app). Regenerate at github.com/settings/tokens if a new Mac needs it |
| Git aliases | Config | ~130 aliases recovered from "git alias" email (2026-04-29, written on Windows), ported to `gitconfig-aliases` in this repo. Activated via `git config --global include.path ~/mac-setup/gitconfig-aliases`. Fixes: latest-tag sort corruption, missing `git` in clean-them-all, Windows quote-escaping in squash-n |

## 2026-08-11

| Item | Type | Notes |
|---|---|---|
| git-autosync | Tool | New repo <https://github.com/tiavelum/git-autosync>: launchd jobs that auto-pull watched clones every 15 min and push on demand via `<repo>/.git/autosync-push` trigger. Installed via its `install.sh`; config in `~/.config/git-autosync/repos` |
| Repos moved to `~/vc` | Config | All local clones now live under `~/vc` (setup-docs, git-autosync, mac-setup); new convention, see repo-location-vc skill. Re-set `git config --global include.path ~/vc/mac-setup/gitconfig-aliases`; updated autosync config paths and re-ran its installer |
| Logi Options+ | App | `cask "logi-options+"` — for the Logitech MX Keys. Purpose: the camera key above the number pad sends "Print Screen", which macOS ignores; in Options+ assign it the screenshot action / ⇧⌘4. **Requires a reboot after install, and the key assignment is a manual step** (not automatable). Details: setup-docs → `setup-04-mx-keys-clipboard-google-apple.md` |
| Maccy | App | `cask "maccy"` — clipboard manager with searchable history; macOS itself only ever keeps the *latest* clipboard item. **Installed** via `brew bundle`. Manual follow-up in its settings: enable "Launch at login", set history size, pick a hotkey (default ⇧⌘C). Details: setup-docs → `setup-04` |
| Brewfile reconciled | Config | `gh` and `pandoc` were installed manually earlier (setup-01 / setup-03) but were missing from the Brewfile — now listed, so a fresh machine gets them from `brew bundle`. Brewfile is now split into "command-line tools" and "apps" |

---

## How to add entries

Append a row under today's date (create the date section if needed):

```markdown
## YYYY-MM-DD

| Item | Type | Notes |
|---|---|---|
| Name | App / Extension / Config / One-off | ... |
```

Types:

- **App** — installable via Homebrew if possible → also add it to `Brewfile`
- **Extension** — browser/VS Code/Office extensions, usually installed from within the host app
- **Config** — settings, accounts, preferences (note whether it syncs via Apple/Google account)
- **One-off** — done once, not part of a fresh-machine setup
