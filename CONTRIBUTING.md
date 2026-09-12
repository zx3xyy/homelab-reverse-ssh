# Contributing

Thanks for helping improve `homelab-reverse-ssh`.

## Before opening a pull request

1. Keep the default path focused on Ubuntu/Debian, OpenSSH, and systemd.
2. Preserve idempotency: running an installer twice should be safe.
3. Do not weaken the tunnel account restrictions or expose the reverse port publicly.
4. Run the test suite:

   ```bash
   ./tests/static-tests.sh
   ```

5. If installation behavior changes, test on a disposable VPS and Home Lab VM.

## Pull requests

- Explain the problem and the chosen trade-off.
- Keep unrelated changes separate.
- Update `README.md` when commands or supported environments change.
- Never commit private keys, public IP addresses tied to a person, tokens, or generated `client-ssh-config` files.

## Reporting bugs

Use the bug-report issue template and include:

- Distribution and version
- OpenSSH and systemd versions
- The exact command used, with addresses and usernames redacted
- Relevant output from `./doctor.sh` and `journalctl`

For security vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.
