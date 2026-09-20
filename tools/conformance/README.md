# Hunspell Conformance Runner

Run MoonSpell against a checked-out Hunspell `tests/` directory.

```bash
python tools/conformance/run.py --suite /path/to/hunspell/tests
```

Reports are written to `conformance-report.md` and `conformance-report.json`. The checked-in baseline is [../../docs/CONFORMANCE.md](../../docs/CONFORMANCE.md).

Use `--filter` to run selected fixtures and `--strict` to fail when any selected
good/wrong fixture does not pass.
