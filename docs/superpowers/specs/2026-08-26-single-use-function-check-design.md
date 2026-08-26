# Add Single-Use Function Candidate Check

## Goal

Provide a repeatable, advisory report of production functions that have zero or one resolved external reference. The report is intended to identify orphan code and one-use compatibility helpers for human review; it must not assume that every single-use function is incorrect.

## Scope

- Scan production TypeScript under `src/**/*.ts`.
- Analyze named top-level `FunctionDeclaration` nodes, named class `MethodDeclaration` nodes, and top-level variables initialized with an arrow function or function expression. Object-literal methods, nested callbacks, constructors, and accessors are excluded because they are commonly callback or framework wiring rather than independently maintainable functions.
- Exclude tests, scripts, generated output, comments, declaration text, and the declaration's own identifier from reference counts.
- Count symbol-resolved references across imports and source files. Self-recursive references do not count as external uses.

## Output

Add `scripts/check-single-use.mjs` and a `functions:check` package script. The command is report-only and exits successfully after printing candidates grouped by zero or one resolved reference.

Each candidate includes:

- declaration path and one-based line number;
- symbol name and declaration kind;
- reference count (`0` or `1`);
- resolved reference path and line when a reference exists.

If no candidates exist, the command prints a clear success message. The output should be deterministic by sorting paths, line numbers, and names.

## Symbol resolution

Use the repository's installed TypeScript compiler API rather than regular expressions. Load `tsconfig.json` with its compiler options, including path aliases and Bundler module resolution, then build a no-emit `Program` from the configured production source files. Use the type checker to canonicalize declaration symbols, and use the language service's `findReferences()` for each candidate so imports, aliases, class members, and structural method calls are resolved using TypeScript's reference engine. Exclude the declaration itself and references inside the candidate's own declaration body.

The checker should handle imported and re-exported symbols without counting an import alias as a separate declaration. Import and export specifiers count as external dependency references because they represent actual symbol edges; the declaration's own `export` modifier does not. It should tolerate unresolved symbols and skip them rather than producing misleading candidates.

## Integration

- Add `pnpm functions:check` to `package.json`.
- Keep the command out of the default `pnpm check` sequence so the normal verification output remains focused and the advisory report does not become a build gate.
- Do not add a runtime dependency; TypeScript is already a development dependency.

## Verification

- Run the new command and inspect candidates manually.
- Confirm known orphan candidates would be reported if reintroduced in a fixture or temporary source change.
- Run `pnpm typecheck` and `pnpm check` to ensure the checker does not affect application validation.
- Run `git diff --check` and verify unrelated worktree changes remain untouched.

## Acceptance criteria

- `pnpm functions:check` runs without additional package installation.
- Candidate counts are based on compiler-resolved symbols, not textual name matches.
- The report identifies zero- and one-use production declarations with stable locations.
- The command is advisory and does not fail because candidates exist.
