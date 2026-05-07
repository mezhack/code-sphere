# ADR-0006: Argon2 for Password Hashing

**Status:** Accepted
**Date:** 2026-04-26
**Decision Makers:** Project lead

## Context

Student passwords are stored in `portal-data/alunos.json`. This file may be backed up, shared between teachers debugging issues, or accidentally exposed. Passwords must be hashed with a modern algorithm that resists offline attacks even if the file leaks.

Students often choose weak passwords (the system requires only 6 characters minimum). The hashing algorithm must therefore be resistant to GPU-accelerated dictionary attacks, not just to brute force.

## Decision

Use **Argon2id** via the `argon2-cffi` library, with the library's default parameters. Hashes are stored in PHC string format (e.g., `$argon2id$v=19$m=65536,t=3,p=4$...`) which embeds the algorithm parameters, allowing future migration without breaking existing hashes.

The portal also handles automatic rehashing: if a stored hash uses outdated parameters (when defaults change in a future library version), the portal re-hashes with current defaults on the next successful login.

## Alternatives Considered

### bcrypt

Pros: mature, widely deployed, fewer obscure attack surfaces.

Rejected because: bcrypt has a 72-byte password limit and is GPU-accelerable in ways Argon2 isn't (because Argon2 is memory-hard). For new projects in 2025, Argon2 is the recommended choice by OWASP, NIST, and most security guidance.

### scrypt

Pros: memory-hard like Argon2, well-vetted.

Rejected because: Argon2 is the OWASP-recommended successor to scrypt, with better tooling and a clearer evolution path.

### PBKDF2

Pros: FIPS-approved, available everywhere.

Rejected because: not memory-hard, vulnerable to GPU acceleration. Not recommended for new applications.

### Plaintext or simple hash (MD5, SHA-256 without salt)

Rejected because: completely unacceptable for any password storage. Mentioned only to be explicit — these are not options.

## Consequences

### Enabled

- Even if `alunos.json` leaks, brute-forcing student passwords is computationally expensive.
- The PHC format allows transparent parameter upgrades over time.
- The library handles salt generation, parameter selection, and constant-time comparison.

### Prevented

- Cannot read student passwords back. (This is a security feature, not a limitation — passwords are only ever verified, never displayed.)
- Cannot easily port to a system that requires a different hash algorithm without re-prompting all users for their passwords.

### New problems introduced

- **Login is intentionally slow** (~50-100 ms per Argon2 verify). This is a security feature but means the portal cannot serve thousands of logins per second. Acceptable since the design target is ~60 logins per class start, not thousands per second.

- **Library is a Python dependency** (argon2-cffi). The portal's Docker image installs it via `requirements.txt`. If this dependency stops being maintained, migration would require rehashing on next login.

## References

- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [argon2-cffi documentation](https://argon2-cffi.readthedocs.io/)
- `portal/app.py` — uses `PasswordHasher` from `argon2`
