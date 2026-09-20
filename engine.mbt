///|
pub(all) struct SpellResult {
  accepted : Bool
  stem : String?
  prefix : String?
  suffix : String?
}

///|
fn flag_tokens(flag_mode : String, flags : String) -> Array[String] {
  let result : Array[String] = []
  if flag_mode == "num" {
    for token in flags.split(",") {
      let value = token.to_owned()
      if !value.is_empty() {
        result.push(value)
      }
    }
  } else if flag_mode == "long" {
    let chars = flags.to_array()
    let mut i = 0
    while i + 1 < chars.length() {
      result.push(chars[i].to_string() + chars[i + 1].to_string())
      i += 2
    }
  } else {
    for c in flags {
      result.push(c.to_string())
    }
  }
  result
}

///|
fn flags_contain(flag_mode : String, flags : String, flag : String) -> Bool {
  if flag.is_empty() {
    false
  } else {
    flag_tokens(flag_mode, flags).contains(flag)
  }
}

///|
fn entry_is_forbidden(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.forbidden_word {
    Some(flag) => flags_contain(config.flag_mode, entry.flags, flag)
    None => false
  }
}

///|
fn entry_needs_affix(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.need_affix {
    Some(flag) => flags_contain(config.flag_mode, entry.flags, flag)
    None => false
  }
}

///|
fn entry_can_be_exact(config : AffixConfig, entry : DicEntry) -> Bool {
  !entry_is_forbidden(config, entry) && !entry_needs_affix(config, entry)
}

///|
fn entry_can_be_affixed(config : AffixConfig, entry : DicEntry) -> Bool {
  !entry_is_forbidden(config, entry)
}

///|
fn condition_width(pattern : String) -> Int {
  let chars = pattern.to_array()
  let mut width = 0
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '[' {
      let mut j = i + 1
      while j < chars.length() && chars[j] != ']' {
        j += 1
      }
      if j >= chars.length() {
        return -1
      }
      width += 1
      i = j + 1
    } else {
      width += 1
      i += 1
    }
  }
  width
}

///|
fn condition_matches_at(pattern : String, text : Array[Char], start : Int) -> Bool {
  let pattern_chars = pattern.to_array()
  let mut pattern_index = 0
  let mut text_index = start
  while pattern_index < pattern_chars.length() {
    if pattern_chars[pattern_index] == '[' {
      let mut end = pattern_index + 1
      while end < pattern_chars.length() && pattern_chars[end] != ']' {
        end += 1
      }
      if end >= pattern_chars.length() || text_index >= text.length() {
        return false
      }
      let negate = pattern_index + 1 < end && pattern_chars[pattern_index + 1] == '^'
      let char_start = if negate { pattern_index + 2 } else { pattern_index + 1 }
      let mut found = false
      for i in char_start..<end {
        if pattern_chars[i] == text[text_index] {
          found = true
          break
        }
      }
      if (negate && found) || (!negate && !found) {
        return false
      }
      pattern_index = end + 1
      text_index += 1
    } else if pattern_chars[pattern_index] == '.' {
      if text_index >= text.length() {
        return false
      }
      pattern_index += 1
      text_index += 1
    } else {
      if text_index >= text.length() || pattern_chars[pattern_index] != text[text_index] {
        return false
      }
      pattern_index += 1
      text_index += 1
    }
  }
  true
}

///|
fn condition_matches(rule : AffixRule, stem : String) -> Bool {
  let condition = rule.condition
  if condition.is_empty() || condition == "." {
    return true
  }
  let width = condition_width(condition)
  let chars = stem.to_array()
  if width < 0 || width > chars.length() {
    return false
  }
  let start = match rule.kind {
    Prefix => 0
    Suffix => chars.length() - width
  }
  condition_matches_at(condition, chars, start)
}
fn ends_with(text : StringView, suffix : String) -> Bool {
  let text_len = text.length()
  let suffix_len = suffix.length()
  if suffix_len > text_len {
    return false
  }
  text.view(start_offset=text_len - suffix_len).to_owned() == suffix
}

///|
pub fn Dictionary::find_entries(self : Dictionary, word : String) -> Array[DicEntry] {
  let result : Array[DicEntry] = []
  for entry in self.entries {
    if entry.word == word {
      result.push(entry)
    }
  }
  result
}

///|
fn exact_result(dictionary : Dictionary, config : AffixConfig, word : String) -> SpellResult? {
  for entry in dictionary.find_entries(word) {
    if entry_can_be_exact(config, entry) {
      return Some({ accepted: true, stem: Some(word), prefix: None, suffix: None, })
    }
  }
  None
}

///|
fn prefix_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  rule : AffixRule,
) -> SpellResult? {
  if rule.add.is_empty() || word.find(rule.add) != Some(0) {
    return None
  }
  let remainder = word.view(start_offset=rule.add.length())
  let stem = rule.strip + remainder.to_owned()
  if !condition_matches(rule, stem) {
    return None
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, rule.flag) && entry_can_be_affixed(config, entry) {
      return Some({ accepted: true, stem: Some(stem), prefix: Some(rule.add), suffix: None, })
    }
  }
  None
}

///|
fn suffix_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  rule : AffixRule,
) -> SpellResult? {
  if rule.add.is_empty() || !ends_with(word, rule.add) {
    return None
  }
  let stem = word.view(end_offset=word.length() - rule.add.length()).to_owned() + rule.strip
  if !condition_matches(rule, stem) {
    return None
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, rule.flag) && entry_can_be_affixed(config, entry) {
      return Some({ accepted: true, stem: Some(stem), prefix: None, suffix: Some(rule.add), })
    }
  }
  None
}

///|
fn twofold_suffix_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  outer : AffixRule,
  inner : AffixRule,
) -> SpellResult? {
  if outer.add.is_empty() || inner.add.is_empty() {
    return None
  }
  if !ends_with(word, outer.add) {
    return None
  }
  let intermediate = word.view(end_offset=word.length() - outer.add.length()).to_owned()
  if !condition_matches(outer, intermediate) {
    return None
  }
  if !flags_contain(config.flag_mode, inner.continuation, outer.flag) {
    return None
  }
  if !ends_with(intermediate.view(), inner.add) {
    return None
  }
  let stem = intermediate.view(end_offset=intermediate.length() - inner.add.length()).to_owned() + inner.strip
  if !condition_matches(inner, stem) {
    return None
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, inner.flag) && entry_can_be_affixed(config, entry) {
      return Some({
        accepted: true,
        stem: Some(stem),
        prefix: None,
        suffix: Some(outer.add),
      })
    }
  }
  None
}
///|
fn cross_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  prefix : AffixRule,
  suffix : AffixRule,
) -> SpellResult? {
  if prefix.add.is_empty() || suffix.add.is_empty() {
    return None
  }
  if !prefix.cross_product || !suffix.cross_product {
    return None
  }
  if word.find(prefix.add) != Some(0) || !ends_with(word, suffix.add) {
    return None
  }
  if prefix.add.length() + suffix.add.length() >= word.length() {
    return None
  }
  let inner = word.view(
    start_offset=prefix.add.length(),
    end_offset=word.length() - suffix.add.length(),
  )
  let stem = prefix.strip + inner.to_owned() + suffix.strip
  if !condition_matches(prefix, stem) || !condition_matches(suffix, stem) {
    return None
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, prefix.flag) &&
      flags_contain(config.flag_mode, entry.flags, suffix.flag) &&
      entry_can_be_affixed(config, entry) {
      return Some({
        accepted: true,
        stem: Some(stem),
        prefix: Some(prefix.add),
        suffix: Some(suffix.add),
      })
    }
  }
  None
}

///|
fn spell_core(dictionary : Dictionary, config : AffixConfig, word : String) -> SpellResult {
  match exact_result(dictionary, config, word) {
    Some(result) => return result
    None => ()
  }
  let view = word.view()
  for rule in config.prefixes {
    match prefix_result(dictionary, config, view, rule) {
      Some(result) => return result
      None => ()
    }
  }
  for rule in config.suffixes {
    match suffix_result(dictionary, config, view, rule) {
      Some(result) => return result
      None => ()
    }
  }
  for outer in config.suffixes {
    for inner in config.suffixes {
      match twofold_suffix_result(dictionary, config, view, outer, inner) {
        Some(result) => return result
        None => ()
      }
    }
  }
  for prefix in config.prefixes {
    for suffix in config.suffixes {
      match cross_result(dictionary, config, view, prefix, suffix) {
        Some(result) => return result
        None => ()
      }
    }
  }
  { accepted: false, stem: None, prefix: None, suffix: None, }
}
///|
fn ascii_lower(text : String) -> String {
  let result = StringBuilder()
  for c in text {
    if c >= 'A' && c <= 'Z' {
      result.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      result.write_char(c)
    }
  }
  result.to_string()
}


///|
fn ascii_upper_char(c : Char) -> Char {
  if c >= 'a' && c <= 'z' {
    (c.to_int() - 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn capitalize_ascii(text : String) -> String {
  let chars = text.to_array()
  if chars.length() == 0 {
    return text
  }
  let result = StringBuilder()
  result.write_char(ascii_upper_char(chars[0]))
  for i in 1..<chars.length() {
    result.write_char(chars[i])
  }
  result.to_string()
}
///|
fn is_all_upper(text : String) -> Bool {
  let mut has_letter = false
  let mut valid = true
  for c in text {
    if c >= 'a' && c <= 'z' {
      valid = false
      break
    }
    if c >= 'A' && c <= 'Z' {
      has_letter = true
    }
  }
  has_letter && valid
}

///|
fn is_capitalized(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 || chars[0] < 'A' || chars[0] > 'Z' {
    return false
  }
  for i in 1..<chars.length() {
    if chars[i] >= 'A' && chars[i] <= 'Z' {
      return false
    }
  }
  true
}

///|
fn strip_trailing_periods(text : String) -> String {
  let mut end = text.length()
  while end > 0 && text.unsafe_get(end - 1) == '.' {
    end -= 1
  }
  if end == text.length() {
    text
  } else {
    text.view(end_offset=end).to_owned()
  }
}

///|
fn case_variant_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> SpellResult? {
  if is_all_upper(word) || is_capitalized(word) {
    let lower = ascii_lower(word)
    if lower != word {
      let result = spell_core(dictionary, config, lower)
      if result.accepted {
        return Some(result)
      }
    }
    let capitalized = capitalize_ascii(lower)
    if capitalized != word {
      let result = spell_core(dictionary, config, capitalized)
      if result.accepted {
        return Some(result)
      }
    }
  }
  None
}

///|
pub fn spell(dictionary : Dictionary, config : AffixConfig, word : String) -> SpellResult {
  let direct = spell_core(dictionary, config, word)
  if direct.accepted {
    return direct
  }
  let without_periods = strip_trailing_periods(word)
  if without_periods != word {
    let bare = spell_core(dictionary, config, without_periods)
    if bare.accepted {
      return bare
    }
    match case_variant_result(dictionary, config, without_periods) {
      Some(result) => return result
      None => ()
    }
  }
  match case_variant_result(dictionary, config, word) {
    Some(result) => return result
    None => ()
  }
  direct
}