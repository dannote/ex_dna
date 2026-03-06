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

## How it works

1. Parse `.ex`/`.exs` files into Elixir AST via `Code.string_to_quoted/2`
2. Normalize: strip metadata → rename variables to positional placeholders → optionally abstract literals
3. Walk every subtree above a mass threshold and compute a BLAKE2b fingerprint
4. Group matching fingerprints — any group of 2+ is a clone
5. Prune nested clones (keep the largest match per location)

## Configuration

All options can be passed to `mix ex_dna` or to `ExDNA.analyze/1`:

| Option | CLI flag | Default | Description |
|--------|----------|---------|-------------|
| `min_mass` | `--min-mass` | 30 | Minimum AST node count for a fragment |
| `min_similarity` | `--min-similarity` | 1.0 | Similarity threshold (future: fuzzy matching) |
| `literal_mode` | `--literal-mode` | `keep` | `keep` = Type-I only, `abstract` = also Type-II |
| `ignore` | `--ignore` | `[]` | Glob patterns to exclude |

## Roadmap

- [x] Phase 1: AST normalization + fingerprinting + Type-I/II detection
- [ ] Phase 2: Anti-unification + refactoring suggestions
- [ ] Phase 3: Type-III fuzzy matching + pipe/guard normalization
- [ ] Phase 4: Macro suggestion engine + behaviour extraction
- [ ] Phase 5: Compiler tracer integration + HTML reporter

## License

MIT
