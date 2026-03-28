# ExDNA 🧬

Code duplication detector for Elixir, inspired by
[jscpd](https://github.com/kucherenko/jscpd) but built on Elixir's native AST
instead of token matching.

Because ExDNA understands code structure — not just text —
`fn(a, b) -> a + b end` and `fn(x, y) -> x + y end` are recognized as the
same code. It also tells you *how* to fix each clone: extract a function, a
macro, or a behaviour callback.

## Features

- **Three clone types** — exact copies (I), renamed variables / changed
  literals (II), and near-miss clones via tree edit distance (III)
- **Multi-clause awareness** — consecutive `def`/`defp` clauses with the same
  name/arity are analyzed as a single unit, catching duplicated pattern-matching
  functions that individual clauses are too small to flag
- **Refactoring suggestions** — extract function, extract macro, extract
  behaviour with `@callback`
- **Smart naming** — suggestions are named after the dominant struct, call,
  or pattern (`build_changeset`, `contact_step`) instead of
  `extracted_function`
- **Pipe normalization** — `x |> f()` and `f(x)` match as the same code
- **Cross-file grouping** — `actions/ ↔ tools/ (6 clones, 298 nodes)`
  instead of listing each pair
- **`@no_clone` annotation** — suppress known/intentional duplicates
- **Incremental `Mix.Task.Compiler`** — only re-analyzes changed files
- **LSP server** — pushes clone diagnostics to your editor alongside
  [Expert](https://github.com/elixir-lang/expert) or ElixirLS
- **Credo integration** — drop-in replacement for `DuplicatedCode`, reuses
  Credo's parsed ASTs
- **CI-ready** — exits with code 1 when clones are found
- **Three output formats** — Credo-style console, JSON, self-contained HTML
- **Fast** — parallel file parsing, 395 files in ~1 second

## Installation

```elixir
def deps do
  [{:ex_dna, "~> 1.2.1", only: [:dev, :test], runtime: false}]
end
```

## Usage

```bash
mix ex_dna                              # scan lib/
mix ex_dna lib/accounts lib/admin       # specific paths
mix ex_dna --literal-mode abstract      # enable Type-II (renamed vars)
mix ex_dna --min-similarity 0.85        # enable Type-III (near-miss)
mix ex_dna --min-mass 50                # fewer, larger clones
mix ex_dna --format json                # machine-readable
mix ex_dna --format html                # browsable report
```

Deep-dive into a specific clone:

```bash
mix ex_dna.explain 3
```

Shows the full anti-unification breakdown — common structure, divergence
points, and the suggested extraction with call sites.

### Programmatic API

```elixir
report = ExDNA.analyze("lib/")
report.clones   #=> [%ExDNA.Detection.Clone{}, ...]
report.stats    #=> %{files_analyzed: 42, total_clones: 3, ...}
```

## Configuration

Options are layered: **defaults → `.ex_dna.exs` → CLI flags**.

Create `.ex_dna.exs` in your project root:

```elixir
%{
  min_mass: 25,
  ignore: ["lib/my_app_web/templates/**"],
  excluded_macros: [:@, :schema, :pipe_through, :plug],
  normalize_pipes: true
}
```

| Option | CLI flag | Default | Description |
|--------|----------|---------|-------------|
| `min_mass` | `--min-mass` | `30` | Minimum AST nodes for a fragment |
| `min_similarity` | `--min-similarity` | `1.0` | Threshold for Type-III (set < 1.0 to enable) |
| `literal_mode` | `--literal-mode` | `keep` | `keep` = Type-I only, `abstract` = also Type-II |
| `normalize_pipes` | `--normalize-pipes` | `false` | Treat `x \|> f()` same as `f(x)` |
| `excluded_macros` | `--exclude-macro` | `[:@]` | Macro calls to skip entirely |
| `parse_timeout` | — | `5000` | Max ms per file (kills hung parses) |
| `ignore` | `--ignore` | `[]` | Glob patterns to exclude |

## Suppressing clones

```elixir
@no_clone true
def validate(params) do
  # intentional duplication, won't be flagged
end
```

## Incremental detection

Add ExDNA as a compiler for automatic detection on `mix compile`:

```elixir
def project do
  [compilers: Mix.compilers() ++ [:ex_dna]]
end
```

Only changed files are re-analyzed. Cache is stored in `.ex_dna_cache` (add to
`.gitignore`).

## Editor integration

ExDNA ships an LSP server that pushes warnings inline on every save. It runs
alongside your primary Elixir LSP.

```bash
mix ex_dna.lsp
```

### Neovim

```lua
vim.lsp.config('ex_dna', {
  cmd = { 'mix', 'ex_dna.lsp' },
  root_markers = { 'mix.exs' },
  filetypes = { 'elixir' },
})
```

## Credo integration

ExDNA ships a Credo check that replaces the built-in `DuplicatedCode` with
full Type-I/II/III detection and refactoring suggestions. It reuses Credo's
already-parsed ASTs — no double parsing.

Add to the `:enabled` list in `.credo.exs`:

```elixir
{ExDNA.Credo, []}
```

And disable the built-in check:

```elixir
{Credo.Check.Design.DuplicatedCode, false}
```

All ExDNA options are available as check params:

```elixir
{ExDNA.Credo, [
  min_mass: 40,
  literal_mode: :abstract,
  excluded_macros: [:@, :schema, :pipe_through],
  normalize_pipes: true,
  min_similarity: 0.85
]}
```

## How it works

1. **Parse** — `Code.string_to_quoted/2` on every `.ex`/`.exs` file (parallel,
   with per-file timeout)
2. **Normalize** — strip line/column metadata → rename variables to positional
   placeholders (`$0`, `$1`) → optionally abstract literals → optionally
   flatten pipes
3. **Fingerprint** — walk every subtree above `min_mass` nodes, hash with
   BLAKE2b
4. **Detect** — group by hash (Type I/II), compare nearby fragments by tree
   edit distance (Type III)
5. **Filter** — prune nested clones, keep the largest match per location
6. **Suggest** — anti-unify each clone pair to compute the common structure,
   generate extract-function/macro/behaviour suggestions

## License

[MIT](LICENSE)
