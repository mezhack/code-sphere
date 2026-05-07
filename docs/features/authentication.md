# Feature: Authentication

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

Students access their own isolated VS Code environments through a shared URL. The system must:

- Identify which student is logging in to route them to the correct container.
- Prevent one student from accessing another student's workspace.
- Force a password change on first login (initial passwords are shared in class for ease of distribution).
- Allow the teacher (admin) to reset any student's password without knowing the old one.

The threat model is **classroom-grade**, not enterprise: defending against curious classmates and accidental cross-access, not state-level adversaries. Strong password storage (Argon2) addresses the realistic risk of `alunos.json` leaking.

## Behavior

### Student First Login (forced password change)

1. Student visits `/` and is redirected to `/login`.
2. Enters username (`alunoXX`) and shared initial password.
3. Portal verifies the password against the Argon2 hash in `alunos.json`.
4. If `precisa_trocar` is true, portal redirects to `/trocar-senha` instead of starting the container.
5. Student enters current password, new password (twice).
6. Portal validates: minimum 6 characters, new ≠ current, confirmation matches.
7. New hash is written to `alunos.json`, `precisa_trocar` is set to false.
8. Student is redirected to `/conectar` to start their session.

### Student Subsequent Login

1. Student visits `/` and is redirected to `/login` (unless they have an active session).
2. Enters username and personal password.
3. Portal verifies hash; on success, redirects to `/conectar`.
4. `/conectar` starts the container if needed and renders the auto-login page.

### Admin Login

1. Admin visits `/admin` directly.
2. Sees admin login form (separate from student login).
3. Enters the admin password (set in `config.env` as `SENHA_ADMIN`).
4. On success, `session["admin"] = True` and admin is redirected to `/admin/painel`.

### Admin Password Reset (any student)

1. From the admin panel, admin clicks "🔑 Senha" on a student row.
2. Confirmation dialog appears.
3. On confirmation, `POST /admin/resetar/<aluno>`.
4. Portal sets the student's hash back to the initial password and `precisa_trocar = true`.
5. Next time that student logs in, they're forced to change again.

### Inputs

- **Login:** `usuario` (string), `senha` (string)
- **Password change:** `atual` (string), `nova` (string), `confirmacao` (string)
- **Admin login:** `senha` (string)
- **Admin reset:** `aluno` (URL parameter)

### Outputs

- Updated `portal-data/alunos.json` with new hashes and metadata
- `session["aluno"]` set on student login (Flask session cookie)
- `session["admin"]` set on admin login
- Flash messages on errors (e.g., "Usuário ou senha inválidos.")

### Edge Cases

- **Username case-insensitivity.** Usernames are lowercased on input. `Aluno01` and `aluno01` resolve to the same account.
- **Whitespace in username.** Stripped via `.strip()`. Empty string after strip is rejected as not-a-user.
- **New password equals old password.** Rejected during change (must be different).
- **Password contains special characters (`@`, `#`, etc.).** Allowed. Argon2 handles arbitrary bytes.
- **Two simultaneous logins from same student.** Both succeed. The second login generates a new container token, invalidating the first session's connection. The first browser will get a 401 on next ping and be redirected to login.
- **Hash needs rehashing (algorithm parameters changed).** Detected via `ph.check_needs_rehash`; portal silently rehashes on next successful login.

### Failure Modes

- **`alunos.json` does not exist.** On startup, portal calls `inicializar_alunos()` which creates entries for all students with the initial password.
- **`alunos.json` is corrupted JSON.** `_load()` returns the default empty dict. Effectively, the file is rebuilt on next save. Pre-existing student passwords are lost in this case (acceptable for classroom-grade threat model; teacher can reset).
- **Admin password not configured.** Falls back to the literal string `"admin"`. The setup script enforces a minimum 8-character admin password.
- **Username does not exist.** Same generic error message as wrong password ("Usuário ou senha inválidos.") to prevent username enumeration.

## Integration Points

- **Container Lifecycle:** Successful login triggers `iniciar_container()` for the student's container.
- **Admin Panel:** Admin password reset writes to the same `alunos.json` that the login flow reads.
- **Sessions storage:** Successful login writes to `sessoes.json` to track activity for the GC.

## Implementation References

- `portal/app.py:login` — student login route
- `portal/app.py:trocar_senha` — password change route
- `portal/app.py:admin_login` — admin login route
- `portal/app.py:admin_resetar_senha` — admin password reset route
- `portal/app.py:inicializar_alunos` — first-run student creation

## Related

- [ADR-0006: Argon2 for password hashing](../decisions/0006-argon2-passwords.md)
- [Feature: Container Lifecycle](./container-lifecycle.md)
- [Feature: Admin Panel](./admin-panel.md)
