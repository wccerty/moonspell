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
fn expand_flag_vector(config : AffixConfig, flags : String) -> String {
  match parse_decimal_count(flags) {
    Some(index) => {
      if index > 0 && index <= config.flag_aliases.length() {
        config.flag_aliases[index - 1]
      } else {
        flags
      }
    }
    None => flags
  }
}

///|
fn flags_contain(config : AffixConfig, flags : String, flag : String) -> Bool {
  if flag.is_empty() {
    false
  } else {
    flag_tokens(config.flag_mode, expand_flag_vector(config, flags)).contains(flag)
  }
}

///|
fn entry_is_forbidden(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.forbidden_word {
    Some(flag) => flags_contain(config, entry.flags, flag)
    None => false
  }
}

///|
fn entry_needs_affix(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.need_affix {
    Some(flag) => flags_contain(config, entry.flags, flag)
    None => false
  }
}

///|
fn entry_keeps_case(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.keep_case {
    Some(flag) => flags_contain(config, entry.flags, flag)
    None => false
  }
}
///|
fn entry_is_only_in_compound(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.only_in_compound {
    Some(flag) => flags_contain(config, entry.flags, flag)
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
fn rule_has_circumfix(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.circumfix {
    Some(flag) => flags_contain(config, rule.continuation, flag)
    None => false
  }
}

///|
fn rule_needs_affix(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.need_affix {
    Some(flag) => flags_contain(config, rule.continuation, flag)
    None => false
  }
}
///|
fn rule_is_only_in_compound(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.only_in_compound {
    Some(flag) => flags_contain(config, rule.continuation, flag)
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
    if flags_contain(config, entry.flags, rule.flag) && entry_can_be_affixed(config, entry) && !rule_is_only_in_compound(config, rule) && !rule_needs_affix(config, rule) && !rule_has_circumfix(config, rule) {
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
    if flags_contain(config, entry.flags, rule.flag) && entry_can_be_affixed(config, entry) && !rule_is_only_in_compound(config, rule) && !rule_needs_affix(config, rule) && !rule_has_circumfix(config, rule) {
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
  if !flags_contain(config, inner.continuation, outer.flag) {
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
    if flags_contain(config, entry.flags, inner.flag) && entry_can_be_affixed(config, entry) && !rule_is_only_in_compound(config, inner) && !rule_is_only_in_compound(config, outer) && !rule_needs_affix(config, outer) {
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
fn twofold_prefix_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  outer : AffixRule,
  inner : AffixRule,
) -> SpellResult? {
  if outer.add.is_empty() || inner.add.is_empty() ||
    word.find(outer.add) != Some(0) {
    return None
  }
  let intermediate = word.view(start_offset=outer.add.length()).to_owned()
  if !condition_matches(outer, intermediate) ||
    !flags_contain(config, inner.continuation, outer.flag) ||
    intermediate.find(inner.add) != Some(0) {
    return None
  }
  let stem = inner.strip + intermediate.view(start_offset=inner.add.length()).to_owned()
  if !condition_matches(inner, stem) {
    return None
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config, entry.flags, inner.flag) && entry_can_be_affixed(config, entry) {
      return Some({
        accepted: true,
        stem: Some(stem),
        prefix: Some(outer.add),
        suffix: None,
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
    let prefix_flag_ok = flags_contain(config, entry.flags, prefix.flag) ||
      flags_contain(config, suffix.continuation, prefix.flag)
    let suffix_flag_ok = flags_contain(config, entry.flags, suffix.flag) ||
      flags_contain(config, prefix.continuation, suffix.flag)
    if prefix_flag_ok && suffix_flag_ok &&
      entry_can_be_affixed(config, entry) &&
      (!rule_has_circumfix(config, prefix) || rule_has_circumfix(config, suffix)) &&
      (!rule_has_circumfix(config, suffix) || rule_has_circumfix(config, prefix)) {
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
    Some(flag) => flags_contain(config, rule.continuation, flag)
    None => false
  }
}

///|
fn affix_compound_forbid(config : AffixConfig, rule : AffixRule) -> Bool {
  match config.compound_forbid {
    Some(flag) => flags_contain(config, rule.continuation, flag)
    None => false
  }
}

///|
fn entry_has_compound_forbid(config : AffixConfig, entry : DicEntry) -> Bool {
  match config.compound_forbid {
    Some(flag) => flags_contain(config, entry.flags, flag)
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
    if flags_contain(config, entry.flags, rule.flag) && entry_can_be_compound(config, entry) {
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
    if flags_contain(config, entry.flags, rule.flag) && entry_can_be_compound(config, entry) {
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
    if flags_contain(config, entry.flags, prefix.flag) &&
      flags_contain(config, entry.flags, suffix.flag) &&
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
    !flags_contain(config, inner.continuation, outer.flag) ||
    !ends_with(intermediate.view(), inner.add) {
    return result
  }
  let stem = intermediate.view(end_offset=intermediate.length() - inner.add.length()).to_owned() + inner.strip
  if !condition_matches(inner, stem) {
    return result
  }
  for entry in dictionary.find_entries(stem) {
    if flags_contain(config, entry.flags, inner.flag) && entry_can_be_compound(config, entry) {
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
    Some(flag) => if flags_contain(config, flags, flag) { return true }
    None => ()
  }
  if is_first {
    match config.compound_begin {
      Some(flag) => flags_contain(config, flags, flag)
      None => false
    }
  } else if is_last {
    match config.compound_end {
      Some(flag) => flags_contain(config, flags, flag)
      None => false
    }
  } else {
    match config.compound_middle {
      Some(flag) => flags_contain(config, flags, flag)
      None => false
    }
  }
}

///|
///|
fn compound_pattern_matches(
  config : AffixConfig,
  pattern : CompoundPattern,
  left_part : String,
  left : CompoundPartMatch,
  right_part : StringView,
  right : CompoundPartMatch,
) -> Bool {
  if pattern.end_zero && (left.prefix || left.suffix) {
    return false
  }
  if !pattern.end_zero && !pattern.end_chars.is_empty() &&
    !ends_with(left_part.view(), pattern.end_chars) {
    return false
  }
  match pattern.end_flag {
    Some(flag) => if !flags_contain(config, left.flags, flag) { return false }
    None => ()
  }
  if !pattern.begin_chars.is_empty() && right_part.find(pattern.begin_chars) != Some(0) {
    return false
  }
  match pattern.begin_flag {
    Some(flag) => if !flags_contain(config, right.flags, flag) { return false }
    None => ()
  }
  true
}

///|
fn compound_boundary_forbidden_by_pattern(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  left_part : String,
  left : CompoundPartMatch,
  boundary : Int,
) -> Bool {
  let mut end = boundary + 1
  while end <= word.length() {
    let right_view = word.view(start_offset=boundary, end_offset=end)
    if dictionary.find_entries(left_part + " " + right_view.to_owned()).length() > 0 {
      return true
    }
    for right in compound_part_matches(dictionary, config, right_view) {
      for pattern in config.compound_patterns {
        if pattern.replacement is None &&
          compound_pattern_matches(config, pattern, left_part, left, right_view, right) {
          return true
        }
      }
    }
    end += 1
  }
  false
}

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
      if !is_last && compound_boundary_forbidden_by_pattern(dictionary, config, word, part, item, end) {
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

priv struct CompoundRuleToken {
  flag : String
  quantifier : String
}

///|
fn parse_compound_rule(pattern : String, flag_mode : String) -> Array[CompoundRuleToken] {
  let chars = pattern.to_array()
  let result : Array[CompoundRuleToken] = []
  let mut index = 0
  while index < chars.length() {
    let flag = if chars[index] == '(' {
      let mut close = index + 1
      while close < chars.length() && chars[close] != ')' {
        close += 1
      }
      if close >= chars.length() {
        return []
      }
      let value = pattern.view(start_offset=index + 1, end_offset=close).to_owned()
      index = close + 1
      value
    } else if flag_mode == "long" && index + 1 < chars.length() {
      let value = chars[index].to_string() + chars[index + 1].to_string()
      index += 2
      value
    } else {
      let value = chars[index].to_string()
      index += 1
      value
    }
    let quantifier = if index < chars.length() && (chars[index] == '*' || chars[index] == '?') {
      let value = chars[index].to_string()
      index += 1
      value
    } else {
      ""
    }
    result.push({ flag, quantifier, })
  }
  result
}

///|
fn compound_rule_match_at(
  tokens : Array[CompoundRuleToken],
  flags : Array[String],
  token_index : Int,
  part_index : Int,
  config : AffixConfig,
) -> Bool {
  if token_index >= tokens.length() {
    return part_index >= flags.length()
  }
  let token = tokens[token_index]
  let can_consume = part_index < flags.length() &&
    flags_contain(config, flags[part_index], token.flag)
  match token.quantifier {
    "" => can_consume && compound_rule_match_at(tokens, flags, token_index + 1, part_index + 1, config)
    "?" =>
      compound_rule_match_at(tokens, flags, token_index + 1, part_index, config) ||
      (can_consume && compound_rule_match_at(tokens, flags, token_index + 1, part_index + 1, config))
    "*" =>
      compound_rule_match_at(tokens, flags, token_index + 1, part_index, config) ||
      (can_consume && compound_rule_match_at(tokens, flags, token_index, part_index + 1, config))
    _ => false
  }
}

///|
fn compound_rule_matches(
  pattern : String,
  flags : Array[String],
  config : AffixConfig,
) -> Bool {
  if flags.length() == 0 {
    return false
  }
  let tokens = parse_compound_rule(pattern, config.flag_mode)
  if tokens.length() == 0 {
    return false
  }
  compound_rule_match_at(tokens, flags, 0, 0, config)
}

///|
fn compound_rule_search(
  dictionary : Dictionary,
  config : AffixConfig,
  word : StringView,
  pattern : String,
  start : Int,
  flags : Array[String],
  max_parts : Int,
) -> Bool {
  if start >= word.length() || flags.length() >= max_parts {
    return false
  }
  let mut end = start + 1
  while end <= word.length() {
    let is_last = end == word.length()
    let part_view = word.view(start_offset=start, end_offset=end)
    if compound_part_length_ok(part_view, config) {
      for item in compound_part_matches(dictionary, config, part_view) {
        if !is_last && (item.prefix || item.suffix) {
          continue
        }
        let next_flags = flags.copy()
        next_flags.push(item.flags)
        if is_last {
          if compound_rule_matches(pattern, next_flags, config) {
            return true
          }
        } else if compound_rule_search(
          dictionary,
          config,
          word,
          pattern,
          end,
          next_flags,
          max_parts,
        ) {
          return true
        }
      }
    }
    end += 1
  }
  false
}

///|
fn compound_rule_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> Bool {
  if config.compound_rules.length() == 0 {
    return false
  }
  for pattern in config.compound_rules {
    if compound_rule_search(dictionary, config, word.view(), pattern, 0, [], 32) {
      return true
    }
  }
  false
}
///|
fn compound_rep_correctable(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> Bool {
  for rule in config.replacements {
    match replacement_candidate(word, rule.from, rule.to) {
      Some(candidate) => {
        if dictionary.find_entries(candidate).length() > 0 {
          return true
        }
      }
      None => ()
    }
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
  let matched = compound_search(dictionary, config, word.view(), 0, 0, "", max_parts)
  matched && !(config.check_compound_rep && compound_rep_correctable(dictionary, config, word))
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
  if config.complex_prefixes {
    for outer in config.prefixes {
      for inner in config.prefixes {
        match twofold_prefix_result(dictionary, config, view, outer, inner) {
          Some(result) => return result
          None => ()
        }
      }
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
  if compound_rule_result(dictionary, config, word) {
    return { accepted: true, stem: None, prefix: None, suffix: None, }
  }
  { accepted: false, stem: None, prefix: None, suffix: None, }
}
///|
fn ascii_lower(text : String) -> String {
  let result = StringBuilder()
  for c in text {
    result.write_char(@unicode.to_lowercase(c))
  }
  result.to_string()
}

///|
fn language_lower(config : AffixConfig, text : String) -> String {
  let result = StringBuilder()
  for c in text {
    if config.language == "tr" && c == 'I' {
      result.write_char('ı')
    } else if config.language == "tr" && c == 'İ' {
      result.write_char('i')
    } else {
      result.write_char(@unicode.to_lowercase(c))
    }
  }
  result.to_string()
}
///|
fn sharp_case_candidates(text : String) -> Array[String] {
  let lower = ascii_lower(text)
  let chars = lower.to_array()
  let mut occurrences = 0
  let mut i = 0
  while i + 1 < chars.length() {
    if chars[i] == 's' && chars[i + 1] == 's' {
      occurrences += 1
      i += 2
    } else {
      i += 1
    }
  }
  if occurrences > 8 {
    occurrences = 8
  }
  let result : Array[String] = []
  let combinations = 1 << occurrences
  for mask in 0..<combinations {
    let builder = StringBuilder()
    let mut index = 0
    let mut bit = 0
    while index < chars.length() {
      if index + 1 < chars.length() && chars[index] == 's' && chars[index + 1] == 's' && bit < occurrences {
        if ((mask >> bit) & 1) == 1 {
          builder.write_char('ß')
        } else {
          builder.write_char('s')
          builder.write_char('s')
        }
        index += 2
        bit += 1
      } else {
        builder.write_char(chars[index])
        index += 1
      }
    }
    let variant = builder.to_string()
    if !result.contains(variant) { result.push(variant) }
    let capitalized = capitalize_ascii(variant)
    if !result.contains(capitalized) { result.push(capitalized) }
  }
  result
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
fn is_uppercase_char(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || c == 'İ' || @unicode.to_lowercase(c) != c
}
///|
fn is_probably_lowercase_char(c : Char) -> Bool {
  if c >= 'a' && c <= 'z' {
    true
  } else {
    let lower = @unicode.to_lowercase(c)
    lower == c && c.to_int() > 127 && c != '.' && c != '\'' && c != '-' && c != '_'
  }
}
///|
fn is_all_upper(text : String) -> Bool {
  let mut has_letter = false
  let mut valid = true
  for c in text {
    if is_uppercase_char(c) {
      has_letter = true
    } else if is_probably_lowercase_char(c) {
      valid = false
      break
    }
  }
  has_letter && valid
}

///|
fn is_capitalized(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 || !is_uppercase_char(chars[0]) {
    return false
  }
  for i in 1..<chars.length() {
    if is_uppercase_char(chars[i]) {
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
fn has_exact_forbidden(dictionary : Dictionary, config : AffixConfig, word : String) -> Bool {
  for entry in dictionary.find_entries(word) {
    if entry_is_forbidden(config, entry) {
      return true
    }
  }
  false
}
///|
fn result_has_forbidden_homonym(
  dictionary : Dictionary,
  config : AffixConfig,
  result : SpellResult,
) -> Bool {
  match result.stem {
    Some(stem) => {
      let lower_stem = ascii_lower(stem)
      for entry in dictionary.entries {
        if ascii_lower(entry.word) == lower_stem && entry_is_forbidden(config, entry) {
          return true
        }
      }
      false
    }
    None => false
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
      let mut has_match = false
      let mut has_non_keepcase = false
      let lower_stem = ascii_lower(stem)
      for entry in dictionary.entries {
        if ascii_lower(entry.word) == lower_stem {
          has_match = true
          if !entry_keeps_case(config, entry) {
            has_non_keepcase = true
          }
        }
      }
      has_match && !has_non_keepcase
    }
    None => false
  }
}
///|
fn apply_conversions(rules : Array[ReplacementRule], word : String) -> String {
  let mut result = word
  let mut iteration = 0
  while iteration < 100 {
    iteration += 1
    let mut best_rule : Int = -1
    let mut best_position = result.length() + 1
    let mut best_length = 0
    for i in 0..<rules.length() {
      match result.find(rules[i].from) {
        Some(position) => {
          let length = rules[i].from.length()
          if position < best_position || (position == best_position && length > best_length) {
            best_rule = i
            best_position = position
            best_length = length
          }
        }
        None => ()
      }
    }
    if best_rule < 0 {
      break
    }
    let rule = rules[best_rule]
    match replace_first(result, rule.from, rule.to) {
      Some(value) => {
        if value == result {
          break
        }
        result = value
      }
      None => break
    }
  }
  result
}

///|
fn apply_iconv(config : AffixConfig, word : String) -> String {
  apply_conversions(config.iconv_rules, word)
}
///|
fn case_variant_result(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> SpellResult? {
  if is_all_upper(word) {
    let lower_word = language_lower(config, word)
    for candidate in generate_candidates(dictionary, config) {
      if language_lower(config, candidate) == lower_word && !has_exact_forbidden(dictionary, config, candidate) {
        let result = spell_core(dictionary, config, candidate)
        if result.accepted {
          return Some(result)
        }
      }
    }
  }
  if config.check_sharps && (is_all_upper(word) || is_capitalized(word)) {
    for candidate in sharp_case_candidates(word) {
      if candidate != word {
        let result = spell_core(dictionary, config, candidate)
        if result.accepted {
          return Some(result)
        }
      }
    }
  }
  if is_all_upper(word) || is_capitalized(word) {
    let lower = language_lower(config, word)
    if lower != word {
      let result = spell_core(dictionary, config, lower)
      if result.accepted && !result_is_keepcase_only(dictionary, config, result) && !result_has_forbidden_homonym(dictionary, config, result) {
        return Some(result)
      }
    }
    let capitalized = capitalize_ascii(lower)
    if capitalized != word {
      let result = spell_core(dictionary, config, capitalized)
      if result.accepted && !result_is_keepcase_only(dictionary, config, result) && !result_has_forbidden_homonym(dictionary, config, result) {
        return Some(result)
      }
    }
  }
  None
}

///|
pub fn spell(dictionary : Dictionary, config : AffixConfig, word : String) -> SpellResult {
  let word = apply_iconv(config, word)
  if has_exact_forbidden(dictionary, config, word) {
    return { accepted: false, stem: None, prefix: None, suffix: None, }
  }
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
