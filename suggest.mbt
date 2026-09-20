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
    if entry_is_forbidden(config, entry) || entry_is_nosuggest(config, entry) || entry.word.contains(" ") {
      continue
    }
    if !entry_needs_affix(config, entry) {
      remember_unique(candidates, entry.word)
    }
    for prefix in config.prefixes {
      if flags_contain(config, entry.flags, prefix.flag) {
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
      if flags_contain(config, entry.flags, suffix.flag) {
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
          flags_contain(config, entry.flags, prefix.flag) &&
          flags_contain(config, entry.flags, suffix.flag) &&
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
fn suggestion_word_is_valid(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> Bool {
  if word.contains(" ") {
    for part in word.split(" ") {
      let token = part.to_owned()
      if token.is_empty() || !spell(dictionary, config, token).accepted {
        return false
      }
    }
    true
  } else {
    spell(dictionary, config, word).accepted
  }
}

///|
fn replace_first(text : String, from : String, to : String) -> String? {
  match text.find(from) {
    Some(index) =>
      Some(
        text.view(end_offset=index).to_owned() +
        to +
        text.view(start_offset=index + from.length()).to_owned(),
      )
    None => None
  }
}

///|
fn replacement_candidate(
  word : String,
  from_raw : String,
  to_raw : String,
) -> String? {
  let from = if from_raw.find("^") == Some(0) {
    from_raw.view(start_offset=1).to_owned()
  } else {
    from_raw
  }
  let anchored_end = from.find("$") == Some(from.length() - 1)
  let from = if anchored_end {
    from.view(end_offset=from.length() - 1).to_owned()
  } else {
    from
  }
  let anchored_start = from_raw.find("^") == Some(0)
  if anchored_start && word.find(from) != Some(0) {
    return None
  }
  if anchored_end && !ends_with(word.view(), from) {
    return None
  }
  let to = to_raw.replace_all(old="_", new=" ")
  match replace_first(word, from, to) {
    Some(candidate) => if candidate == word { None } else { Some(candidate) }
    None => None
  }
}

///|
fn add_rule_suggestions(
  result : Array[Suggestion],
  dictionary : Dictionary,
  config : AffixConfig,
  candidates : Array[String],
  limit : Int,
) -> Unit {
  for candidate in candidates {
    if result.length() >= limit {
      return
    }
    let output = apply_conversions(config.oconv_rules, candidate)
    if !result.any(item => item.word == output) &&
      suggestion_word_is_valid(dictionary, config, candidate) {
      result.push({
        word: output,
        distance: levenshtein_distance(candidate, candidate),
      })
    }
  }
}

///|
fn rep_candidates(word : String, config : AffixConfig) -> Array[String] {
  let result : Array[String] = []
  for rule in config.replacements {
    match replacement_candidate(word, rule.from, rule.to) {
      Some(candidate) => result.push(candidate)
      None => ()
    }
  }
  result
}

///|
fn entry_is_nosuggest(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.no_suggest {
    Some(flag) => flags_contain(config, entry.flags, flag)
    None => false
  }
}

///|
fn key_candidates(word : String, config : AffixConfig) -> Array[String] {
  let result : Array[String] = []
  if config.keyboard.is_empty() {
    return result
  }
  let groups = config.keyboard.split("|").to_array()
  for i in 0..<word.length() {
    let original = word.unsafe_get(i).to_int()
    for group in groups {
      let chars = group.to_array()
      for j in 0..<chars.length() {
        if chars[j].to_int() == original {
          if j > 0 {
            result.push(word.view(end_offset=i).to_owned()+chars[j-1].to_string()+word.view(start_offset=i+1).to_owned())
          }
          if j + 1 < chars.length() {
            result.push(word.view(end_offset=i).to_owned()+chars[j+1].to_string()+word.view(start_offset=i+1).to_owned())
          }
        }
      }
    }
  }
  result
}

///|
fn case_candidates(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> Array[String] {
  let result : Array[String] = []
  let lower_word = language_lower(config, word)
  for candidate in generate_candidates(dictionary, config) {
    if language_lower(config, candidate) == lower_word && candidate != word {
      result.push(candidate)
    }
  }
  result
}
///|
fn parse_map_elements(mapping : String) -> Array[String] {
  let chars = mapping.to_array()
  let result : Array[String] = []
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '(' {
      let mut close = index + 1
      while close < chars.length() && chars[close] != ')' {
        close += 1
      }
      if close < chars.length() {
        result.push(mapping.view(start_offset=index + 1, end_offset=close).to_owned())
        index = close + 1
      } else {
        result.push(chars[index].to_string())
        index += 1
      }
    } else {
      result.push(chars[index].to_string())
      index += 1
    }
  }
  result
}

///|
fn map_candidates(word : String, config : AffixConfig) -> Array[String] {
  let result : Array[String] = []
  for mapping in config.maps {
    let elements = parse_map_elements(mapping)
    for i in 0..<elements.length() {
      for j in 0..<elements.length() {
        if i != j {
          match replace_first(word, elements[i], elements[j]) {
            Some(candidate) => result.push(candidate)
            None => ()
          }
        }
      }
    }
  }
  result
}
///|
fn try_candidates(word : String, config : AffixConfig, limit : Int) -> Array[String] {
  let result : Array[String] = []
  if config.try_chars.is_empty() {
    return result
  }
  let chars = word.to_array()
  for c in config.try_chars {
    for i in 0..<=chars.length() {
      if result.length() >= limit {
        return result
      }
      result.push(
        word.view(end_offset=i).to_owned() +
        c.to_string() +
        word.view(start_offset=i).to_owned(),
      )
    }
  }
  for i in 0..<chars.length() {
    for c in config.try_chars {
      if result.length() >= limit {
        return result
      }
      result.push(
        word.view(end_offset=i).to_owned() +
        c.to_string() +
        word.view(start_offset=i + 1).to_owned(),
      )
    }
  }
  for i in 0..<chars.length() {
    if result.length() >= limit {
      return result
    }
    result.push(
      word.view(end_offset=i).to_owned() +
      word.view(start_offset=i + 1).to_owned(),
    )
  }
  for i in 0..<(chars.length() - 1) {
    if result.length() >= limit {
      return result
    }
    result.push(
      word.view(end_offset=i).to_owned() +
      chars[i + 1].to_string() +
      chars[i].to_string() +
      word.view(start_offset=i + 2).to_owned(),
    )
  }
  result
}
///|
pub fn suggest(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
  limit : Int,
) -> Array[Suggestion] {
  let dictionary = normalized_dictionary(config, dictionary)
  if limit <= 0 || spell(dictionary, config, word).accepted {
    return []
  }
  let result : Array[Suggestion] = []
  add_rule_suggestions(result, dictionary, config, case_candidates(dictionary, config, word), limit)
  add_rule_suggestions(result, dictionary, config, key_candidates(word, config), limit)
  add_rule_suggestions(result, dictionary, config, rep_candidates(word, config), limit)
  add_rule_suggestions(result, dictionary, config, map_candidates(word, config), limit)
  add_rule_suggestions(result, dictionary, config, try_candidates(word, config, limit * 200), limit)
  let candidates = generate_candidates(dictionary, config)
  for candidate in candidates {
    let output = apply_conversions(config.oconv_rules, candidate)
    if result.any(item => item.word == output) {
      continue
    }
    let distance = levenshtein_distance(word, candidate)
    if distance <= 3 {
      insert_ranked(result, { word: output, distance, }, limit)
    }
  }
  result
}
