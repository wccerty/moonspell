# Hunspell Compatibility

Reference version: **Hunspell v1.7.3**.

MoonSpell currently does not claim full compatibility.

| Area | Status |
|---|---|
| `.dic` parser | Partial: word, flags, morphology |
| `.aff` parser | Partial: SET, FLAG, TRY, WORDCHARS, AF, AM, PFX, SFX, REP, MAP |
| Exact lookup | Partial: raw dictionary word lookup |
| Case handling | Partial: lowercase/all-caps/title-case and trailing periods |
| PFX / SFX | Partial: single prefix or suffix, cross product |
| Affix conditions | Partial: literals, `.`, character classes, negation, multi-character boundaries |
| Cross product | Partial: prefix + suffix |
| Continuation flags | Partial: twofold suffix continuation |
| Compound words | Planned |
| REP / MAP / TRY | Partial: parsed; TRY not yet used by suggestions |
| Edit-distance suggestions | Partial: generated dictionary/affix candidates and Levenshtein ranking |
| Official fixture runner | Implemented; base good/wrong fixtures pass |

## Current baseline

Full-suite baseline on 2026-09-20:

- Good-word fixtures: `25/112`
- Wrong-word fixtures: `78/95`
- Suggestion Top-1: `75/173`
- Suggestion exact-list matches: `62/173`

The parser and engine are under active development. Full Compatibility may only be declared after all supported Hunspell fixture behavior and suggestion output are verified against the pinned reference version.