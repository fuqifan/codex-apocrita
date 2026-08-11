# Experimental Windows/WSL support

Codex Desktop supports Windows SSH hosts, but this integration relies on OpenSSH `ControlMaster` whenever Apocrita requires an interactive password after public-key authentication.

Native Win32 OpenSSH has historically lacked the Unix-socket behavior needed for this feature. Therefore native Windows is not a supported v0.1 installation target for password-required accounts.

WSL uses Linux OpenSSH and can run the installer and `apo`, but Codex Desktop may use the Windows SSH executable and Windows SSH configuration instead of WSL's. Treat WSL integration as experimental. Check whether your Desktop version passes all of these checks:

1. `apo ssh status` succeeds inside WSL.
2. Codex Desktop discovers the same concrete alias.
3. Desktop reuses the authenticated master without another password prompt.
4. `apo doctor --runtime` shows the expected Slurm job and compute node.

If your account has an approved key-only endpoint (passwordless), native Windows may work without multiplexing.
