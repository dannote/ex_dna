# ExDNA 🧬

Code duplication detector powered by Elixir AST analysis.

Unlike token-based tools (jscpd, etc.), ExDNA works directly with Elixir's
native AST. It normalizes variable names, strips metadata, and fingerprints
subtrees — so `fn(a, b) -> a + b end` and `fn(x, y) -> x + y end` are
recognized as the same code.

## Installation

Add `ex_dna` to your `mix.exs`:

```elixir
def deps do
  [{:ex_dna, "~> 0.1.0", only: [:dev, :test], runtime: false}]
end
```

## Usage

```bash
# Scan your project
$ mix ex_dna

# Scan specific paths
$ mix ex_dna lib/my_app/accounts lib/my_app/admin

# Detect renamed-variable clones (Type-II)
$ mix ex_dna --literal-mode abstract

# Lower the sensitivity (fewer, larger clones)
$ mix ex_dna --min-mass 50

# JSON output
$ mix ex_dna --format json
```

### Programmatic API

```elixir
report = ExDNA.analyze("lib/")
report.clones       # list of %ExDNA.Detection.Clone{}
report.stats        # %{files_analyzed: 42, total_clones: 3, ...}
```

## Clone types

| Type | What it catches |
|------|----------------|
| **Type I** | Exact copies (modulo whitespace and comments) |
| **Type II** | Same structure with renamed variables and/or different literals |
| **Type III** | Near-miss clones — same structure ± a few changed/added/removed lines |

## How it works

1. Parse `.ex`/`.exs` files into Elixir AST via `Code.string_to_quoted/2`
2. Normalize: strip metadata → flatten pipes (optional) → rename variables → optionally abstract literals
3. Walk every subtree above a mass threshold and compute a BLAKE2b fingerprint
4. Group matching fingerprints — any group of 2+ is a clone (Type I/II)
5. For Type-III: compare non-matching fragments within ±30% mass using tree edit distance
6. Prune nested clones (keep the largest match per location)
7. Generate refactoring suggestions via anti-unification

## Configuration

Options are applied in layers: **defaults → `.ex_dna.exs` → CLI flags/API opts**.

Create `.ex_dna.exs` in your project root for project-level defaults:

```elixir
%{
  min_mass: 25,
  ignore: ["lib/my_app_web/templates/**"],
  excluded_macros: [:@, :schema, :pipe_through, :plug],
  normalize_pipes: true
}
```

All options can also be passed to `mix ex_dna` or to `ExDNA.analyze/1`:

| Option | CLI flag | Default | Description |
|--------|----------|---------|-------------|
| `min_mass` | `--min-mass` | 30 | Minimum AST node count for a fragment |
| `min_similarity` | `--min-similarity` | 1.0 | Similarity threshold. Values < 1.0 enable Type-III near-miss detection |
| `literal_mode` | `--literal-mode` | `keep` | `keep` = Type-I only, `abstract` = also Type-II |
| `normalize_pipes` | `--normalize-pipes` | `false` | Treat `x \|> f()` the same as `f(x)` |
| `excluded_macros` | `--exclude-macro` | `[:@]` | Macro names to skip (module attrs excluded by default) |
| `parse_timeout` | — | `5000` | Max ms per file for parsing (kills hung files) |
| `ignore` | `--ignore` | `[]` | Glob patterns to exclude |

## Refactoring suggestions

ExDNA doesn't just find clones — it tells you how to fix them. Using
*anti-unification* (computing the most specific generalization of two ASTs),
it identifies what's common and what differs, then suggests an extracted
function with the differences as parameters:

```
┃
┃ [I]  #3  19 nodes
┃   admin_service.ex:7
┃   user_service.ex:7
┃
┃     params
┃     |> Map.put(:inserted_at, DateTime.utc_now())
┃     |> validate_required([:name, :email])
┃     |> validate_format(:email, ~r/@/)
┃
┃   → Extract: defp extracted_function(arg0)
┃     admin_service.ex:7 → extracted_function(params)
┃     user_service.ex:7  → extracted_function(attrs)
┃
```

Use `mix ex_dna.explain N` to deep-dive into a specific clone with the full
anti-unification breakdown.

## Suppressing clones

Add `@no_clone true` before a function to exclude it from detection:

```elixir
@no_clone true
def validate(params) do
  # This won't be flagged as a duplicate
end
```

## Incremental detection

Add ExDNA as a compiler for automatic detection on every `mix compile`:

```elixir
def project do
  [compilers: Mix.compilers() ++ [:ex_dna]]
end
```

Results are cached in `.ex_dna_cache` — only changed files are re-analyzed.

## Roadmap

- [x] Phase 1: AST normalization + fingerprinting + Type-I/II detection
- [x] Phase 2: Anti-unification + refactoring suggestions
- [x] Phase 3: Type-III fuzzy matching + pipe normalization
- [x] Hardening: parallel parsing, `.ex_dna.exs` config, excluded macros, parse timeout
- [x] Output: Credo-style console reporter, JSON reporter, HTML reporter
- [x] Validation: 0 false positives across real-world projects (100–400 files each)
- [x] Smart suggestion names — derived from AST (struct names, call patterns,
  pipe chains) instead of generic `extracted_function`
- [x] Cross-file clone grouping — clones sharing the same directories are
  grouped with a header: `actions/ ↔ tools/ (6 clones, 298 nodes)`
- [x] Macro suggestion engine — detects repeated boilerplate (3+ fragments,
  module-level, struct literals) and suggests `defmacro`
- [x] Behaviour extraction — when multiple modules implement the same `def`
  with identical structure, suggests `@callback`
- [x] `Mix.Task.Compiler` — incremental detection via mtime-based cache,
  only re-analyzes changed files
- [x] `@no_clone` annotation — add `@no_clone true` before a `def` to
  suppress it from detection
- [ ] LSP server via GenLSP — push clone diagnostics to editors alongside
  [Expert](https://expert-lsp.org/) (Elixir's official LSP)

## License

MIT
