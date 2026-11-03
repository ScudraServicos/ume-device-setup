# UME device setup

Small, public tools that help UME people prepare their own computer.

| Tool | What it does |
|---|---|
| [`ume-account-migrate.sh`](ume-account-migrate.sh) | Renames your computer login to the UME standard name (the part of your work email before `@`), so JumpCloud can take over your existing account. Linux and macOS. |
| [`skills/ume-account-migrate/`](skills/ume-account-migrate/SKILL.md) | The same flow as an AI-assistant skill (Claude, Hermes): it checks your computer, explains everything in plain language and walks you through it. |

---

## Easiest: ask your AI assistant

Copy this sentence and paste it into **Claude** (Desktop app, claude.ai or Claude Code)
or **Hermes**:

```text
Read https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v2026.11.03/skills/ume-account-migrate/SKILL.md and follow it step by step to prepare my computer for JumpCloud.
```

That's it. The assistant checks your computer, explains everything in plain language and
tells you exactly what to paste in Terminal, one step at a time. It never asks for your
passwords: you only type those into Terminal.

**Want it installed for next time?** (optional) Afterwards, just say
*"prepare my computer for JumpCloud"*.

| Assistant | Install the skill once |
|---|---|
| Claude Desktop / claude.ai | Download [`ume-account-migrate-skill.zip`](https://github.com/ScudraServicos/ume-device-setup/releases/latest), then **Settings → Capabilities → Skills → Upload skill** and pick the zip. |
| Claude Code | Paste in Terminal: `mkdir -p ~/.claude/skills/ume-account-migrate && curl -fsSL https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v2026.11.03/skills/ume-account-migrate/SKILL.md -o ~/.claude/skills/ume-account-migrate/SKILL.md` |
| Hermes Agent | Paste in Terminal: `mkdir -p ~/.hermes/skills/ume-account-migrate && curl -fsSL https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v2026.11.03/skills/ume-account-migrate/SKILL.md -o ~/.hermes/skills/ume-account-migrate/SKILL.md` |

No assistant? Follow the steps below yourself: it is the same flow.

---

## Rename my computer login (for everyone)

**Why:** JumpCloud only takes over your current account if your login name is
exactly the first part of your UME email. Example: `maria.silva@…` needs the login
name `maria.silva`. If it is different, JumpCloud creates a second, empty account.

**What stays the same:** all your files, apps, settings, saved passwords, and your
login password.

**Time:** about 15 minutes. You will log out and back in twice.

### Step by step

1. Save your work. Keep your laptop plugged in.
   **Mac users: do not restart the Mac until all steps are done** (logging out is fine).
2. Open the **Terminal** app and paste this command, then press Enter:

   ```bash
   f=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v2026.11.03/ume-account-migrate.sh -o "$f" && bash "$f"
   ```

3. Type your UME work email when asked. The tool checks your computer:
   - **"All good!"** → nothing to do. Continue with JumpCloud enrollment.
   - **Does not match** → it explains what will happen and asks you to type `yes`.
4. **Run 1** (your own account): the tool creates a temporary helper account,
   **UME Migration**, with a password you choose. Log out, then log in as *UME Migration*.
   If welcome/setup screens appear, skip them all.
5. **Run 2** (as UME Migration): open Terminal and paste **the same command**. It
   renames your account. Log out, then log in with your **new name** and your
   **usual password**.
6. **Run 3** (as your new name): open Terminal and paste **the same command** one last
   time. It checks everything and removes the helper account.

| | Mac | Linux (Ubuntu / GNOME) |
|---|---|---|
| Open Terminal | <kbd>Cmd</kbd>+<kbd>Space</kbd>, type *Terminal*, Enter | <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>T</kbd> |
| Log out | Apple menu → **Log Out** | Top-right menu → **Power** → **Log Out** |
| Never | Restart, or **Switch User** | **Switch User** or Lock instead of logging out |

Keep this page open on your phone: you need the command in each run.
7. **Install JumpCloud** (the tool shows these steps too):
   1. Open the JumpCloud activation email from the company, follow it, and set your
      new password.
   2. Sign in to the JumpCloud User Portal (link in that email).
   3. Go to **Security → Device Enrollment** and follow the steps to download and
      install the JumpCloud agent.
   4. If JumpCloud asks to **take over** an existing account, **accept**: it must be
      your standard name. If it wants to create a new account instead, stop and
      contact your InfraSec team.
   5. From then on, your computer password is your JumpCloud password.

At every step the tool tells you exactly what to do next. If anything looks wrong,
it stops and changes nothing else. Share its message with your InfraSec team.

**Prefer an AI assistant?** Use the [skill](skills/ume-account-migrate/SKILL.md): it
does the check for you and guides you step by step.

### Options

| Option | Use |
|---|---|
| `--check` | Only check; never changes anything. |
| `--email you@…` | Skip the email question. |
| `--cancel` | Right after run 1, from your own account: removes the helper account and stops. |

Add options at the end of the command, after `bash "$f"`.

### If something goes wrong

| Situation | What to do |
|---|---|
| "does not have admin rights" | Your account is not an admin on this computer. Contact your InfraSec team. |
| Asked for a password after the command | It is **your login password** for the account you are logged in as. Nothing shows while typing. |
| "UME Migration" is not on the login screen (Linux) | Click **Not listed?** and type `ume-migrate`. |
| Forgot the helper password after run 1 | Log in to your own account (unchanged so far) and run the command with `--cancel`. Then start again. |
| Your new name is not on the login screen | Login screens often show your full name. Pick that, or type the new name. |
| "already exists" | Another account with your standard name exists already. Contact your InfraSec team. |
| "still logged in (maybe with 'Switch User')" | You switched users instead of logging out. Go back to that account, log out (menu above), log in again as the account the box names, paste the command. |
| Anything else | Contact your InfraSec team. A full record is in `/var/log/ume-account-migrate/`. |

---

## How it works (for reviewers)

- **Rename in place, never copy.** The user ID stays the same, so file ownership,
  keychain / GNOME keyring, FileVault, app permissions (macOS privacy settings) and
  Homebrew keep working. No data is copied and no file inside the home folder is edited.
- **Temporary helper admin.** An OS will not rename an account that is logged in, and
  a user cannot safely rename themselves. Run 1 creates `ume-migrate`, run 2 (as that
  helper) renames, run 3 (as the renamed user) verifies and deletes the helper.
- **Old path keeps working.** A symlink `old home → new home` covers any app or config
  that remembered the absolute path.
- **Linux:** `usermod -l` / `-d -m`, `groupmod -n` for the private group, `/etc/subuid`
  and `/etc/subgid`, AccountsService, systemd linger, mail and cron spool files,
  `sudoers.d` entries (whole-word replacement, validated by `visudo -c` first).
  eCryptfs and systemd-homed accounts are refused.
- **macOS:** `dscl` RecordName change, group memberships moved to the new short name,
  home folder moved, NFSHomeDirectory updated, `diskutil apfs updatePreboot /` so the
  FileVault unlock screen shows the new name.
- **Safety:** a check first; a plain-language plan; a typed `yes` before each change;
  prompts read from `/dev/tty`; every command logged with its undo command
  (`UNDO:` lines) in `/var/log/ume-account-migrate/`; passwords never logged;
  state in a root-owned file (`/var/lib/…` Linux, `/var/db/…` macOS), parsed, never sourced.
- **macOS compatibility:** runs on the built-in `/bin/bash` 3.2.

### Tests

```bash
tests/linux-e2e.sh ubuntu:24.04
```

Disposable Docker container; drives all three runs, `--check` and `--cancel` through a
real terminal (`expect`) as the real users, then checks UID, home, symlink, data, group,
subuid, sudoers, crontab, admin rights, state, logs (undo lines present, no passwords).
Verified on `ubuntu:24.04`, `debian:12`, `fedora:41`.

Not covered by containers (test manually before a release): a graphical login (GDM/
AccountsService, GNOME keyring) and **all of macOS** (FileVault on, reboot after run 3,
keychain, privacy permissions, Homebrew).

### Releases

- **CalVer** tags: `vYYYY.MM.DD`, a second release on the same day: `vYYYY.MM.DD.1`.
- `VERSION` in the script must equal the tag (without `v`). The script prints its own
  pinned download command from it, so a release = bump `VERSION`, update the command in
  this README and the skill, tag.
- Publish the SHA-256 of `ume-account-migrate.sh` in the release notes.

### Contributing: this repository is public

Never commit secrets (keys, tokens, passwords, enrollment/connect keys) or internal
information (people's names or usernames, internal hostnames, project IDs, internal
links, chat channels, rollout plans). Examples use made-up names such as `msilva`.
See [SECURITY.md](SECURITY.md) to report a problem.
