---
name: ume-account-migrate
description: Use when a UME person needs their Linux or Mac login name to match the UME standard (the part of their work email before '@') before JumpCloud enrollment, or asks to "prepare my computer for JumpCloud", "rename my user/account", "fix my username for JumpCloud", or "check if my computer is ready for JumpCloud". Checks the computer first; if a change is needed, explains it in plain language and guides the person through a 3-run copy-paste command.
---

# UME account migration (Linux / macOS)

You are helping a person who may not be technical. Use short sentences, no jargon,
one step at a time. Answer in the person's language.

**Why this exists:** JumpCloud only takes over the person's existing computer account
if the login name equals the part of their UME email before `@`
(`maria.silva@…` → `maria.silva`). Otherwise it creates a second, empty account.

## Rules for you (the assistant)

- **Never run the migration yourself.** It needs the person's keyboard (passwords, a
  typed `yes`) and two log-outs, which end your session. You may only run the read-only
  checks below. The person runs the migration command in their own **Terminal** app.
- Never ask for, repeat, or store any password. Passwords are typed only into Terminal.
- Do not invent steps. The tool prints exactly what to do next; help the person read it.
- Windows is not supported. Tell the person to contact their InfraSec team.

## Step 0: check first (always)

1. **Find the UME work email.** Use what you already know if it is available: the
   signed-in account email in your context, or `git config --global user.email` if you
   can run commands. Otherwise ask: "What is your UME work email?"
   Always confirm it: "Is **<email>** your UME work email?"
2. **Standard name** = the part before `@`, lowercase.
3. **Current login name and home folder.**
   - If you can run commands, run (read-only): `id -un` and `echo "$HOME"`.
   - Otherwise ask the person to open **Terminal**, paste `whoami; echo $HOME`, and send
     you the two lines.
4. **Compare:**
   - Login name **equals** the standard name **and** the home folder ends with
     `/<standard name>`:
     tell them **"All good, your computer already uses the UME standard name. Nothing
     to change."** Then go straight to **"When it is done: install JumpCloud"**, below.
   - Anything else: go to "Explain", below.

   If you can run commands, you may also confirm with the tool's read-only check (it
   never changes anything):

   ```bash
   f=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v2026.11.03.1/ume-account-migrate.sh -o "$f" && bash "$f" --check --email <email>
   ```

## Explain (only when a change is needed)

Say, in your own words and in plain language:

- Your login name will change from **<current>** to **<standard>**.
- Your files, apps, settings, saved passwords and your login password **stay the same**.
- It takes about **15 minutes**. You will **log out and log back in twice**.
- Before starting: save your work, close apps, keep the laptop plugged in.
- **Mac: do not restart** until everything is done (logging out is fine).
- You will paste **the same command 3 times**, in 3 different logins:
  1. **Your account now.** It creates a temporary helper account called
     **UME Migration**; you choose its password (only needed today).
  2. **As UME Migration.** A Terminal window opens by itself and renames your account
     (if it does not open, paste the same command).
  3. **As your new name**, with your usual password. It checks everything and removes
     the helper account.
- How to do the desktop steps (tell them when they reach each one):
  - **Open Terminal:** Mac: Cmd+Space, type *Terminal*, Enter. Linux (Ubuntu/GNOME):
    Ctrl+Alt+T.
  - **Log out:** Mac: Apple menu → Log Out. Linux: top-right menu → Power → Log Out.
  - **Never** use *Switch User* or *Lock* instead of logging out, and on a Mac never restart.
  - The first login to *UME Migration* may show welcome/setup screens: skip them all.

Ask: "Ready to start?" Only then give the command.

## The command

Ask the person to open **Terminal**, paste this, and press Enter:

```bash
f=$(mktemp) && curl -fsSL https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v2026.11.03.1/ume-account-migrate.sh -o "$f" && bash "$f"
```

Tell them to **save this command somewhere they can reach after logging out**
(for example a note on their phone, or this chat on their phone), because they need it
again in run 3 (run 2 normally opens by itself). It is also always on the public page
https://github.com/ScudraServicos/ume-device-setup (no login needed).

What they will see:
- A question for their email, then a check.
- A password prompt: it is **the password of the account they are logged in as**.
  Nothing shows while typing; that is normal.
- A plan, then `Type yes to continue`. They type `yes`.
- A **WHAT TO DO NOW** box at the end of every run. They follow it.

After each log-in, they can come back to you (for example from their phone, or by
opening the assistant again) and say which run they are on.

## Troubleshooting

| They say / see | Tell them |
|---|---|
| "does not have admin rights" | Their account is not an admin. Contact the InfraSec team. |
| Password is rejected | It is the login password of the account they are in now (in run 2: the UME Migration password they chose). |
| UME Migration is not on the login screen (Linux) | Click **Not listed?** and type `ume-migrate`. |
| No Terminal window opened in UME Migration (or they closed it) | Open Terminal and paste the same command. Mac: or double-click **Continue UME migration** on the desktop. |
| Forgot the UME Migration password (after run 1) | Log in to their own account (not changed yet) and paste the command with ` --cancel` at the end. Then start again. |
| New name is not on the login screen | Login screens often show the full name; pick that or type the new name. Password is the usual one. |
| "already exists" | Another account with the standard name exists. Contact the InfraSec team. Do not try to fix it. |
| "still logged in (maybe with 'Switch User')" | They switched users instead of logging out. Go back to that account, log out, log in again as the account the box names, paste the command. |
| "Run 1 is already done" / "Run 2 is already done" | They are in the wrong account for this step. Follow the box: log out and log in as the account it names. |
| Any other red `[X]` message | Nothing else was changed. Contact the InfraSec team and share the message. The full record is in `/var/log/ume-account-migrate/`. |

## When it is done: install JumpCloud

The tool says **"Migration finished"** (or "All good" at the check) and shows the
username for JumpCloud. Then guide them, one step at a time:

1. **Activate JumpCloud.** Open the JumpCloud activation email from the company and
   follow it. Set the new password it asks for. Accept any other JumpCloud permission
   email the company sends with it.
2. **Open the JumpCloud User Portal** (the link is in the activation email) and sign in.
3. Go to **Security → Device Enrollment**. Find this computer's system (Mac or Linux)
   and follow the steps shown there to **download and install the JumpCloud agent**.
   On a Mac it installs like any app; on Linux the portal shows the exact command to
   paste in Terminal. (Never ask for, or paste, any enrollment key in this chat.)
4. If JumpCloud asks to **take over** an existing account, **accept**: it must be the
   account named **<standard name>**. If it suggests creating a new account instead,
   **stop** and contact the InfraSec team (the names do not match).
5. After enrollment, the computer's login password becomes the **JumpCloud password**,
   and they stay in sync while the JumpCloud agent runs.

If anything is interrupted or looks wrong during enrollment, stop and contact the
InfraSec team. Do not retry alone on the computer they need for work.
