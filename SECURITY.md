# Security policy

## Supported versions

Security fixes are applied to the latest commit on `main`.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose a Home Lab, VPS, private key, or SSH account.

Use GitHub's private vulnerability reporting feature for this repository. Include a minimal reproduction, affected versions, and suggested mitigation when available. Please redact real IP addresses, usernames, hostnames, public keys, and logs containing personal infrastructure details.

Until a fix is available, stop the tunnel with:

```bash
sudo systemctl disable --now homelab-reverse-ssh
```

If a tunnel key may have leaked, remove its line from the VPS tunnel user's `authorized_keys`, then generate a new key before reconnecting.
