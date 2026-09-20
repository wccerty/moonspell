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
fn entry_keeps_case(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.keep_case {
    Some(flag) => flags_contain(config.flag_mode, entry.flags, flag)
    None => false
  }
}
///|
fn entry_is_only_in_compound(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.only_in_compound {
    Some(flag) => flags_contain(config.flag_mode, entry.flags, flag)
    None => false
  }
}

///|
fn entry_can_be_exact(config : AffixConfig, entry : DicEntry) -> Bool {
  !entry_is_forbidden(config, entry) &&
  !entry_needs_affix(config, entry) &&
  !entry_is_only_in_compound(config, entry)
}

///|
fn entry_can_be_affixed(config : AffixConfig, entry : DicEntry) -> Bool {
  !entry_is_forbidden(config, entry) && !entry_is_only_in_compound(config, entry)
}

///|
fn rule_is_only_in_compound(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.only_in_compound {
    Some(flag) => flags_contain(config.flag_mode, rule.continuation, flag)
    None => false
  }
}
///|
fn entry_can_be_compound(config : AffixConfig, entry : DicEntry) -> Bool {
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
    if flags_contain(config.flag_mode, entry.flags, rule.flag) && entry_can_be_affixed(config, entry) && !rule_is_only_in_compound(config, rule) {
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
    if flags_contain(config.flag_mode, entry.flags, rule.flag) && entry_can_be_affixed(config, entry) && !rule_is_only_in_compound(config, rule) {
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
    if flags_contain(config.flag_mode, entry.flags, inner.flag) && entry_can_be_affixed(config, entry) && !rule_is_only_in_compound(config, inner) && !rule_is_only_in_compound(config, outer) {
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

priv struct CompoundPartMatch {
  flags : String
  prefix : Bool
  suffix : Bool
  prefix_permit : Bool
  suffix_permit : Bool
  forbid : Bool
}

///|
fn affix_compound_permit(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.compound_permit {
    Some(flag) => flags_contain(config.flag_mode, rule.continuation, flag)
    None => false
  }
}

///|
fn affix_compound_forbid(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.compound_forbid {
    Some(flag) => flags_contain(config.flag_mode, rule.continuation, flag)
    None => false
  }
}

///|
fn entry_has_compound_forbid(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.compound_forbid {
    Some(flag) => flags_contain(config.flag_mode, entry.flags, flag)
    None => false
  }
}
///|
fn exact_part_matches(
  dictionary : Dictionary,
  config : AffixConfig,
  part : String,
) -> Array[CompoundPartMatch] {
  let result : Array[CompoundPartMatch] = []
  for entry in dictionary.find_entries(part) {
    if entry_can_be_compound(config, entry) && !entry_needs_affix(config, entry) {
      result.push({ flags: entry.flags, prefix: false, suffix: false, prefix_permit: false, suffix_permit: false, forbid: entry_has_compound_forbid(config, entry), })
    }
  }
  result
}

///|
fn prefix_part_matches(
  dictionary : Dictionary,
  config : AffixConfig,
  part : StringView,
  rule : AffixRule,
) -> Array[CompoundPartMatch] {
  let result : Array[CompoundPartMatch] = []
  if rule.add.is_empty() || part.find(rule.add) != Some(0) {
    return result
  }
  let stem = rule.strip + part.view(start_offset=rule.add.length()).to_owned()
  if !condition_matches(rule, stem) {
    return result
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, rule.flag) && entry_can_be_compound(config, entry) {
      result.push({ flags: entry.flags + rule.continuation, prefix: true, suffix: false, prefix_permit: affix_compound_permit(config, rule), suffix_permit: false, forbid: affix_compound_forbid(config, rule), })
    }
  }
  result
}

///|
fn suffix_part_matches(
  dictionary : Dictionary,
  config : AffixConfig,
  part : StringView,
  rule : AffixRule,
) -> Array[CompoundPartMatch] {
  let result : Array[CompoundPartMatch] = []
  if rule.add.is_empty() || !ends_with(part, rule.add) {
    return result
  }
  let stem = part.view(end_offset=part.length() - rule.add.length()).to_owned() + rule.strip
  if !condition_matches(rule, stem) {
    return result
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, rule.flag) && entry_can_be_compound(config, entry) {
      result.push({ flags: entry.flags + rule.continuation, prefix: false, suffix: true, prefix_permit: false, suffix_permit: affix_compound_permit(config, rule), forbid: affix_compound_forbid(config, rule), })
    }
  }
  result
}

///|
fn cross_part_matches(
  dictionary : Dictionary,
  config : AffixConfig,
  part : StringView,
  prefix : AffixRule,
  suffix : AffixRule,
) -> Array[CompoundPartMatch] {
  let result : Array[CompoundPartMatch] = []
  if prefix.add.is_empty() || suffix.add.is_empty() ||
    !prefix.cross_product || !suffix.cross_product ||
    part.find(prefix.add) != Some(0) || !ends_with(part, suffix.add) ||
    prefix.add.length() + suffix.add.length() >= part.length() {
    return result
  }
  let inner = part.view(
    start_offset=prefix.add.length(),
    end_offset=part.length() - suffix.add.length(),
  )
  let stem = prefix.strip + inner.to_owned() + suffix.strip
  if !condition_matches(prefix, stem) || !condition_matches(suffix, stem) {
    return result
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, prefix.flag) &&
      flags_contain(config.flag_mode, entry.flags, suffix.flag) &&
      entry_can_be_compound(config, entry) {
      result.push({ flags: entry.flags + prefix.continuation + suffix.continuation, prefix: true, suffix: true, prefix_permit: affix_compound_permit(config, prefix), suffix_permit: affix_compound_permit(config, suffix), forbid: affix_compound_forbid(config, prefix) || affix_compound_forbid(config, suffix), })
    }
  }
  result
}

///|
fn twofold_suffix_part_matches(
  dictionary : Dictionary,
  config : AffixConfig,
  part : StringView,
  outer : AffixRule,
  inner : AffixRule,
) -> Array[CompoundPartMatch] {
  let result : Array[CompoundPartMatch] = []
  if outer.add.is_empty() || inner.add.is_empty() || !ends_with(part, outer.add) {
    return result
  }
  let intermediate = part.view(end_offset=part.length() - outer.add.length()).to_owned()
  if !condition_matches(outer, intermediate) ||
    !flags_contain(config.flag_mode, inner.continuation, outer.flag) ||
    !ends_with(intermediate.view(), inner.add) {
    return result
  }
  let stem = intermediate.view(end_offset=intermediate.length() - inner.add.length()).to_owned() + inner.strip
  if !condition_matches(inner, stem) {
    return result
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config.flag_mode, entry.flags, inner.flag) && entry_can_be_compound(config, entry) {
      result.push({ flags: entry.flags + inner.continuation + outer.continuation, prefix: false, suffix: true, prefix_permit: false, suffix_permit: affix_compound_permit(config, outer), forbid: affix_compound_forbid(config, outer), })
    }
  }
  result
}

///|
fn compound_part_matches(
  dictionary : Dictionary,
  config : AffixConfig,
  part : StringView,
) -> Array[CompoundPartMatch] {
  let result = exact_part_matches(dictionary, config, part.to_owned())
  for rule in config.prefixes {
    for item in prefix_part_matches(dictionary, config, part, rule) {
      result.push(item)
    }
  }
  for rule in config.suffixes {
    for item in suffix_part_matches(dictionary, config, part, rule) {
      result.push(item)
    }
  }
  for outer in config.suffixes {
    for inner in config.suffixes {
      for item in twofold_suffix_part_matches(dictionary, config, part, outer, inner) {
        result.push(item)
      }
    }
  }
  for prefix in config.prefixes {
    for suffix in config.suffixes {
      for item in cross_part_matches(dictionary, config, part, prefix, suffix) {
        result.push(item)
      }
    }
  }
  result
}

///|
fn compound_boundary_has_triple(word : StringView, position : Int) -> Bool {
  if position <= 0 || position >= word.length() {
    return false
  }
  let left = word.unsafe_get(position - 1)
  let right = word.unsafe_get(position)
  if left != right {
    return false
  }
  (position > 1 && word.unsafe_get(position - 2) == left) ||
  (position + 1 < word.length() && word.unsafe_get(position + 1) == right)
}

///|
fn compound_boundary_has_bad_case(word : StringView, position : Int) -> Bool {
  if position <= 0 || position >= word.length() {
    return false
  }
  let left = word.unsafe_get(position - 1).to_int()
  let right = word.unsafe_get(position).to_int()
  if left == 45 || right == 45 {
    return false
  }
  (left >= 65 && left <= 90) || (right >= 65 && right <= 90)
}
///|
fn compound_role_matches(
  config : AffixConfig,
  flags : String,
  is_first : Bool,
  is_last : Bool,
) -> Bool {
  match config.compound_flag {
    Some(flag) => if flags_contain(config.flag_mode, flags, flag) { return true }
    None => ()
  }
  if is_first {
    match config.compound_begin {
      Some(flag) => flags_contain(config.flag_mode, flags, flag)
      None => false
    }
  } else if is_last {
    match config.compound_end {
      Some(flag) => flags_contain(config.flag_mode, flags, flag)
      None => false
    }
  } else {
    match config.compound_middle {
      Some(flag) => flags_contain(config.flag_mode, flags, flag)
      None => false
    }
  }
}

///|
fn compound_part_length_ok(part : StringView, config : AffixConfig) -> Bool {
  part.length() >= config.compound_min ||
  (part.length() == 1 && part.unsafe_get(0).to_int() == 45)
}
///|
fn compound_search(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  start : Int,
  part_count : Int,
  previous_part : String,
  max_parts : Int,
) -> Bool {
  if start >= word.length() || part_count >= max_parts {
    return false
  }
  let mut end = start + 1
  while end <= word.length() {
    let is_first = start == 0
    let is_last = end == word.length()
    let part_view = word.view(start_offset=start, end_offset=end)
    if !compound_part_length_ok(part_view, config) {
      end += 1
      continue
    }
    let part = part_view.to_owned()
    let part_matches = compound_part_matches(dictionary, config, part_view)
    let mut part_forbidden = false
    if !is_last {
      for candidate in part_matches {
        if candidate.forbid {
          part_forbidden = true
          break
        }
      }
    }
    if part_forbidden {
      end += 1
      continue
    }
    for item in part_matches {
      let role_ok = compound_role_matches(config, item.flags, is_first, is_last)
      if !role_ok {
        continue
      }
      if !is_first && item.prefix && !item.prefix_permit {
        continue
      }
      if !is_last && item.suffix && !item.suffix_permit {
        continue
      }
      if config.check_compound_dup && is_last && previous_part == part {
        continue
      }
      if config.check_compound_triple && compound_boundary_has_triple(word, end) {
        continue
      }
      if config.check_compound_case && compound_boundary_has_bad_case(word, end) {
        continue
      }
      if is_last {
        if part_count >= 1 {
          return true
        }
      } else if compound_search(
        dictionary,
        config,
        word,
        end,
        part_count + 1,
        part,
        max_parts,
      ) {
        return true
      }
    }
    end += 1
  }
  false
}

///|
fn compound_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> Bool {
  let max_parts = if config.compound_word_max > 0 {
    config.compound_word_max
  } else {
    8
  }
  if word.length() < config.compound_min * 2 {
    return false
  }
  compound_search(dictionary, config, word.view(), 0, 0, "", max_parts)
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
  if compound_result(dictionary, config, word) {
    return { accepted: true, stem: None, prefix: None, suffix: None, }
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
fn result_is_keepcase_only(
  dictionary : Dictionary,
  config : AffixConfig,
  result : SpellResult,
) -> Bool {
  match result.stem {
    Some(stem) => {
      let entries = dictionary.find_entries(stem)
      if entries.length() == 0 {
        true
      } else {
        let mut has_non_keepcase = false
        for entry in entries {
          if !entry_keeps_case(config, entry) {
            has_non_keepcase = true
            break
          }
        }
        !has_non_keepcase
      }
    }
    None => false
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
      if result.accepted && !result_is_keepcase_only(dictionary, config, result) {
        return Some(result)
      }
    }
    let capitalized = capitalize_ascii(lower)
    if capitalized != word {
      let result = spell_core(dictionary, config, capitalized)
      if result.accepted && !result_is_keepcase_only(dictionary, config, result) {
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
