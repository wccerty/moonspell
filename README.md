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

## Development

```bash
moon check
moon test
moon run cmd/main
moon build --target native
moon run --target native cmd/main
```

## Compatibility policy

- Hunspell v1.7.3 is the behavioral reference.
- Compatibility claims must be backed by official fixtures.
- Unsupported directives must be reported explicitly, never ignored silently.
- Suggestion compatibility is measured by candidate set and ordering.

See [COMPATIBILITY.md](COMPATIBILITY.md) and [docs/PLAN.md](docs/PLAN.md).

## License

Apache-2.0. Third-party notices are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).