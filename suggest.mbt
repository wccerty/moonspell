///|
pub(all) struct Suggestion {
  word : String
  distance : Int
}

///|
fn remember_unique(items : Array[String], word : String) -> Unit {
  if !items.contains(word) {
    items.push(word)
  }
}

///|
fn remove_prefix_strip(stem : String, strip : String) -> String? {
  if strip.is_empty() {
    Some(stem)
  } else if stem.find(strip) == Some(0) {
    Some(stem.view(start_offset=strip.length()).to_owned())
  } else {
    None
  }
}

///|
fn remove_suffix_strip(stem : String, strip : String) -> String? {
  if strip.is_empty() {
    Some(stem)
  } else if ends_with(stem.view(), strip) {
    Some(stem.view(end_offset=stem.length() - strip.length()).to_owned())
  } else {
    None
  }
}

///|
fn generate_candidates(dictionary : Dictionary, config : AffixConfig) -> Array[String] {
  let candidates : Array[String] = []
  for entry in dictionary.entries {
    if entry_is_forbidden(config, entry) {
      continue
    }
    if !entry_needs_affix(config, entry) {
      remember_unique(candidates, entry.word)
    }
    for prefix in config.prefixes {
      if flags_contain(config.flag_mode, entry.flags, prefix.flag) {
        match remove_prefix_strip(entry.word, prefix.strip) {
          Some(base) =>
            if condition_matches(prefix, entry.word) {
              remember_unique(candidates, prefix.add + base)
            }
          None => ()
        }
      }
    }
    for suffix in config.suffixes {
      if flags_contain(config.flag_mode, entry.flags, suffix.flag) {
        match remove_suffix_strip(entry.word, suffix.strip) {
          Some(base) =>
            if condition_matches(suffix, entry.word) {
              remember_unique(candidates, base + suffix.add)
            }
          None => ()
        }
      }
    }
    for prefix in config.prefixes {
      for suffix in config.suffixes {
        if prefix.cross_product && suffix.cross_product &&
          flags_contain(config.flag_mode, entry.flags, prefix.flag) &&
          flags_contain(config.flag_mode, entry.flags, suffix.flag) &&
          condition_matches(prefix, entry.word) && condition_matches(suffix, entry.word) {
          match remove_prefix_strip(entry.word, prefix.strip) {
            Some(without_prefix) =>
              match remove_suffix_strip(without_prefix, suffix.strip) {
                Some(base) => remember_unique(candidates, prefix.add + base + suffix.add)
                None => ()
              }
            None => ()
          }
        }
      }
    }
  }
  candidates
}

///|
pub fn levenshtein_distance(left : String, right : String) -> Int {
  let a = left.to_array()
  let b = right.to_array()
  let mut previous = Array::make(b.length() + 1, 0)
  for j in 0..<=b.length() {
    previous[j] = j
  }
  for i in 1..<=a.length() {
    let current = Array::make(b.length() + 1, 0)
    current[0] = i
    for j in 1..<=b.length() {
      let substitution = previous[j - 1] + (if a[i - 1] == b[j - 1] { 0 } else { 1 })
      let insertion = current[j - 1] + 1
      let deletion = previous[j] + 1
      current[j] = if substitution <= insertion && substitution <= deletion {
        substitution
      } else if insertion <= deletion {
        insertion
      } else {
        deletion
      }
    }
    previous = current
  }
  previous[b.length()]
}

///|
fn insert_ranked(result : Array[Suggestion], candidate : Suggestion, limit : Int) -> Unit {
  let mut inserted = false
  for i in 0..<result.length() {
    let current = result[i]
    if candidate.distance < current.distance ||
      (candidate.distance == current.distance && candidate.word < current.word) {
      result.insert(i, candidate)
      inserted = true
      break
    }
  }
  if !inserted {
    result.push(candidate)
  }
  if result.length() > limit {
    ignore(result.pop())
  }
}

///|
pub fn suggest(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
  limit : Int,
) -> Array[Suggestion] {
  if limit <= 0 || spell(dictionary, config, word).accepted {
    return []
  }
  let candidates = generate_candidates(dictionary, config)
  let result : Array[Suggestion] = []
  for candidate in candidates {
    let distance = levenshtein_distance(word, candidate)
    if distance <= 3 {
      insert_ranked(result, { word: candidate, distance, }, limit)
    }
  }
  result
}