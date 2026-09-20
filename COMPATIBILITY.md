# Hunspell Compatibility

Reference version: **Hunspell v1.7.3**.

MoonSpell currently does not claim full compatibility.

| Area | Status |
|---|---|
| `.dic` parser | Partial: word, flags, morphology |
| `.aff` parser | Partial: SET, FLAG, TRY, WORDCHARS, AF, AM, PFX, SFX, REP, MAP, PHONE, MAXNGRAMSUGS |
| Exact lookup | Partial: raw dictionary word lookup |
| Case handling | Partial: Unicode case, Turkish I, CHECKSHARPS, KEEPCASE |
| PFX / SFX | Partial: single prefix or suffix, cross product |
| Affix conditions | Partial: literals, `.`, character classes, negation, multi-character boundaries |
| Cross product | Partial: prefix + suffix |
| Continuation flags | Partial: twofold suffix/prefix, complex prefixes, circumfix |
| Compound words | Partial: flags, begin/middle/end, min/max, dup/case/triple, permit/forbid, COMPOUNDRULE, basic pattern/rep |
| REP / MAP / PHONE / TRY | Partial: REP/MAP/TRY, dictionary `ph:` rules, PHONE transformations, ICONV/OCONV |
| Suggestions | Partial: Hunspell-style grouped suggestions, word pairs, NGRAM ranking, PHONE candidates, REP/MAP/TRY |
| Official fixture runner | Implemented; base good/wrong fixtures pass |

## Current baseline

Full-suite baseline on 2026-09-20:

- Good-word fixtures: `85/112`
- Wrong-word fixtures: `80/95`
- Suggestion Top-1: `124/173`
- Suggestion exact-list matches: `106/173`

The parser and engine are under active development. Full Compatibility may only be declared after all supported Hunspell fixture behavior and suggestion output are verified against the pinned reference version.

The suggestion totals use the same fixture mapping as Hunspell `-a`: entries that produce no suggestion are not paired with a `.sug` row.
