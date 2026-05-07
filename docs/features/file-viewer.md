# Feature: File Viewer

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

During class, the teacher often wants to see what a specific student is writing without interrupting them or waiting for the student to share their screen. This is the digital equivalent of walking around the classroom and looking over shoulders.

The file viewer reads each student's workspace directly from disk (the bind-mounted `./alunos/alunoXX/workspace/` directory) and renders text files with syntax highlighting in the admin panel.

## Behavior

### Browse a Student's Workspace

1. Admin clicks "📁 Arquivos" on a student row in the admin panel.
2. Browser navigates to `/admin/arquivos/<aluno>`.
3. Portal walks the workspace directory recursively (skipping hidden files starting with `.`).
4. Builds a tree structure of folders and files with sizes.
5. Renders an HTML tree where:
   - Folders are clickable to expand/collapse.
   - Files are links to the file viewer.
   - Each file shows an icon based on extension (🐍 for `.py`, 📝 for `.md`, etc.).
   - File size is shown next to the name.

### View a File's Content

1. Admin clicks a file link.
2. Browser navigates to `/admin/arquivo/<aluno>/<path>`.
3. Portal:
   a. Resolves the path safely (rejects path traversal).
   b. If file size > 500 KB, refuses with "Arquivo muito grande para exibir."
   c. If extension is in the text-extension whitelist (`.py`, `.txt`, `.md`, etc.), reads as UTF-8 with `errors="replace"`.
   d. Otherwise, refuses with "Arquivo binário."
4. Renders an HTML page with:
   - Path breadcrumb showing student and file path.
   - File content in a `<pre><code>` block.
   - Syntax highlighting via highlight.js (loaded from cdnjs).
   - Press `R` to refresh — reloads the page to show latest saved content.

### Inputs

- `<aluno>` — student username (URL parameter).
- `<path>` — relative path within the student's workspace (URL parameter).

### Outputs

- HTML page with file tree (browser view).
- HTML page with file content (viewer page).

### Edge Cases

- **Path traversal attempt** (e.g., `/admin/arquivo/aluno01/../aluno02/file.py`).
  Portal resolves the path with `Path.resolve()` and verifies it's still under the student's workspace. If not, returns 403.
- **File deleted between tree render and viewer click.** Returns 404.
- **File with invalid UTF-8 bytes.** `errors="replace"` substitutes invalid bytes with `?`. The file is still readable.
- **Empty file.** Renders normally; the code block is empty.
- **Very large file (e.g., 50 MB log).** Refused with the generic "muito grande" message.
- **Hidden directory (`.config`, `.git`).** Excluded from the tree. The teacher cannot accidentally see code-server internals.

### Failure Modes

- **Workspace directory missing** (`./alunos/alunoXX/workspace/` doesn't exist).
  Tree renders empty with "Nenhum arquivo encontrado" message.
- **Permission denied reading a file.** `PermissionError` is caught silently in the tree walk; that subdirectory is skipped. In the viewer, it returns the generic read error.
- **Bind mount not configured.** `/alunos` inside the portal container is empty, so all students appear empty. Setup script ensures the mount is in place.

## Privacy and Pedagogy

Students are informed in their workspace's `LEIA-ME.md` that the teacher can view their files — this is the digital equivalent of circling the classroom during exercises. This transparency is intentional: surveillance without disclosure is hostile, but teaching with visibility into student work is normal pedagogical practice.

Real-time editing is **not** observed. The viewer shows the file as last saved on disk — when the student presses Ctrl+S or auto-save fires (every 1 second by default; see [vscode-defaults](#vscode-defaults)). Code in unsaved buffers is invisible to the teacher.

## Integration Points

- **Admin Panel:** the "📁 Arquivos" button is rendered for every student row.
- **Authentication:** admin session required.
- **Volume mount:** the portal container has `./alunos:/alunos:ro` (read-only) bind mount in `docker-compose.yml`.

## Implementation References

- `portal/app.py:admin_arquivos` — workspace tree route
- `portal/app.py:admin_ver_arquivo` — file viewer route
- `portal/app.py:listar_arvore` — recursive directory walk
- `portal/templates/admin_arquivos.html` — tree UI
- `portal/templates/admin_arquivo.html` — file viewer UI
- `gerar.sh` — adds `./alunos:/alunos:ro` mount and `LEIA-ME.md` privacy notice

## Related

- [Feature: Admin Panel](./admin-panel.md)
- [ADR-0007: PUID/PGID for student volumes](../decisions/0007-puid-pgid-911.md)
