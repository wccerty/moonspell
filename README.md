# MoonSpell

MoonSpell is a pure-MoonBit, Hunspell-compatible spelling engine.

Its goal is to parse Hunspell `.aff` and `.dic` dictionaries, perform affix and compound-word checks, and generate ranked spelling suggestions without wrapping the C++ Hunspell implementation.

## Status

Current milestone: core .aff/.dic parsing, exact lookup, PFX/SFX checking, cross product, and basic ranked suggestions. The compatibility target is **Hunspell v1.7.3**, but full compatibility is not claimed until the complete upstream conformance suite passes.

## Planned API

```text
load(aff_path, dic_path, options) -> Result<Dictionary, LoadError>
spell(dictionary, word) -> SpellResult
suggest(dictionary, word, limit) -> Array<Suggestion>
explain(dictionary, word) -> DecisionTrace
validate(aff_path, dic_path) -> ValidationReport
```

## CLI

```bash
moon run cmd/main -- validate <aff> <dic>
moon run cmd/main -- check <aff> <dic> <word>...
moon run cmd/main -- suggest <aff> <dic> <word> --limit 10
```

Example with an installed en_US dictionary:

```bash
moon run --target native cmd/main -- check /path/to/en_US.aff /path/to/en_US.dic hello exsample
moon run --target native cmd/main -- suggest /path/to/en_US.aff /path/to/en_US.dic exsample --limit 5
```

## Development

```bash
moon check --target all
moon test
moon run cmd/main -- version
moon build --target native
moon run --target native cmd/main -- version
```

## Compatibility policy

- Hunspell v1.7.3 is the behavioral reference.
- Compatibility claims must be backed by official fixtures.
- Unsupported directives must be reported explicitly, never ignored silently.
- Suggestion compatibility is measured by candidate set and ordering.

See [COMPATIBILITY.md](COMPATIBILITY.md), [the conformance baseline](docs/CONFORMANCE.md), and [docs/PLAN.md](docs/PLAN.md).

## License

Apache-2.0. Third-party notices are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).