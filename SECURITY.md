# Security

These scripts run with admin rights on people's computers. If you find a problem
(a bug that could change the wrong account, lose data, leak a password, or let
someone else run code), please report it **privately**:

- Use **"Report a vulnerability"** on this repository's **Security** tab (GitHub private
  vulnerability reporting). Do not open a public issue.

Please include the version (`bash ume-account-migrate.sh --version`), the operating
system, and the steps to reproduce. Do not include passwords or personal data.

## Verifying what you run

- Use only the pinned command from the README (it points at a release tag, not a branch).
- Each release lists the SHA-256 of the script. To check it before running:

  ```bash
  curl -fsSL <url-from-the-readme> -o ume-account-migrate.sh
  shasum -a 256 ume-account-migrate.sh   # compare with the release notes
  less ume-account-migrate.sh             # read it
  bash ume-account-migrate.sh
  ```
