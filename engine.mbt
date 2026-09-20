///|
pub(all) struct SpellResult {
  accepted : Bool
  stem : String?
  prefix : String?
  suffix : String?
}

///|
fn flags_contain(flag_mode : String, flags : String, flag : String) -> Bool {
  if flag.is_empty() {
    false
  } else if flag_mode == "num" {
    flags.split(",").any(item => item.to_owned() == flag)
  } else {
    // char mode is exact; long mode is conservative until non-overlapping
    // two-character flag matching is added.
    flags.contains(flag)
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
fn condition_matches_char(pattern : String, c : Char) -> Bool {
  let chars = pattern.to_array()
  if chars.length() == 0 || pattern == "." {
    return true
  }
  if chars.length() >= 3 && chars[0] == '[' && chars[chars.length() - 1] == ']' {
    let negate = chars[1] == '^'
    let start = if negate { 2 } else { 1 }
    let mut found = false
    for i in start..<(chars.length() - 1) {
      if chars[i] == c {
        found = true
        break
      }
    }
    return if negate { !found } else { found }
  }
  chars.length() == 1 && chars[0] == c
}

///|
fn condition_matches(rule : AffixRule, stem : String) -> Bool {
  let chars = stem.to_array()
  if chars.length() == 0 {
    return false
  }
  match rule.kind {
    Prefix => condition_matches_char(rule.condition, chars[0])
    Suffix => condition_matches_char(rule.condition, chars[chars.length() - 1])
  }
}

///|
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
pub fn spell(dictionary : Dictionary, config : AffixConfig, word : String) -> SpellResult {
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