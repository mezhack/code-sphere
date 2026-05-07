# Sala de Aula Docker — Documentation

This documentation follows **Specification-Driven Development (SDD)** principles. Specifications are written in structured natural language, versioned alongside code, and serve as the source of truth for both human contributors and AI agents implementing or modifying features.

## Navigation

### For understanding the system
Start with the [Architecture Overview](./architecture.md) — it describes what the system does, its components, and how they interact at a high level.

### For making decisions
The [Architecture Decision Records (ADRs)](./decisions/) explain *why* the system is the way it is. Each ADR captures a specific design choice, the alternatives considered, and the trade-offs accepted. Read these before proposing structural changes.

### For implementing or modifying features
The [Feature Specifications](./features/) describe each feature in detail: what problem it solves, how it behaves, what edge cases exist, and what the contract is with other parts of the system. AI agents implementing changes should treat these specs as authoritative.

### For running the system
The [Operations Guides](./operations/) cover installation, daily usage, troubleshooting, and upgrading. These are end-user oriented.

## Documentation Structure

```
docs/
├── README.md                ← this file
├── architecture.md          ← system-level overview
├── decisions/               ← why we built it this way (ADRs)
├── features/                ← what each feature does (specs)
└── operations/              ← how to run the system (guides)
```

## How AI Agents Should Use This

When asked to implement, modify, or debug a feature:

1. **Read the relevant feature spec first** in `docs/features/`. The spec defines the contract — the expected behavior, inputs, outputs, and edge cases.
2. **Check related ADRs** in `docs/decisions/`. If your change conflicts with a decision, surface that conflict explicitly rather than silently overriding it.
3. **Update the spec when behavior changes**. The spec is the source of truth, not the code. If the implementation drifts from the spec, the spec is right unless the change is intentional and the spec needs updating.
4. **Add new ADRs for non-trivial decisions**. If you're choosing between alternatives that future maintainers will need to understand, document the choice.

## Versioning

Documentation is versioned with the code. The current system version is in `version.json` at the project root. Each release bumps the version following [Semantic Versioning](https://semver.org/):

- **PATCH** — bug fixes, no behavior change
- **MINOR** — new features, backward-compatible
- **MAJOR** — breaking changes

When making changes that affect documented behavior, update the relevant spec in the same commit as the code change.

## Contributing to Documentation

See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to propose changes. The short version:

- Specs use the template in [features/README.md](./features/README.md)
- ADRs use the template in [decisions/README.md](./decisions/README.md)
- All documentation is in English for international consistency
- Code examples should match the actual codebase
