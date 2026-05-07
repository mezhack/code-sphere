# Feature Specifications

This directory contains the specifications for each feature of the platform. Specifications are written in structured natural language and serve as the contract between intent and implementation.

## Why Specs Matter

A spec answers four questions:

1. **What problem does this feature solve?** (Context)
2. **How should it behave?** (Behavior)
3. **What can go wrong?** (Edge cases and failure modes)
4. **What does it depend on or affect?** (Contracts and integrations)

When implementing, modifying, or debugging a feature, the spec is the source of truth. Code may drift; the spec defines what the code *should* do.

## Format

Each feature spec follows this template:

```markdown
# Feature: <Name>

**Status:** Implemented | In Progress | Proposed | Deprecated
**Owner:** <person or role>
**Last Updated:** YYYY-MM-DD

## Context

What problem does this feature solve? Who benefits? Why is it needed?

## Behavior

What does this feature do? Describe the happy path step by step.

### Inputs

What triggers this feature? What are the inputs (parameters, events, state)?

### Outputs

What does this feature produce? What state does it change?

### Edge Cases

What unusual situations must be handled correctly?

### Failure Modes

What can go wrong? How should the system respond?

## Integration Points

What other features or components does this depend on or affect?

## Implementation References

Where is this implemented in the codebase?

## Related

- ADRs that constrain this feature
- Other features that interact with it
```

## Index

| Feature | Status | Description |
|---------|--------|-------------|
| [Authentication](./authentication.md) | Implemented | Student login, password change, admin login |
| [Container Lifecycle](./container-lifecycle.md) | Implemented | Spawn, health-check, idle cleanup |
| [Auto-Reconnect](./auto-reconnect.md) | Implemented | Browser detects container shutdown and reconnects |
| [Admin Panel](./admin-panel.md) | Implemented | Real-time stats, container management, password reset |
| [File Viewer](./file-viewer.md) | Implemented | Admin reads student workspace files |
| [Cloudflare HTTPS](./cloudflare-https.md) | Implemented | HTTPS without domain or router config |
| [Version Check](./version-check.md) | Implemented | Notify admin of newer versions on GitHub |
| [Interactive Setup](./interactive-setup.md) | Implemented | First-run configuration wizard |

## Adding a New Feature Spec

1. Create `feature-name.md` using the template above.
2. Add an entry to the index in this file.
3. If the feature involves significant architectural choices, add an ADR.
4. Reference relevant ADRs and other features at the bottom.
5. When implementing, link the spec from code comments at the entry point.

## Modifying a Feature

When changing an existing feature's behavior:

1. Update the spec **before or with** the code change. The spec must reflect the new behavior.
2. If the change is breaking (alters the contract with users or other features), bump the major version.
3. If the change rejects an alternative previously discussed in an ADR, link to or update the ADR.
