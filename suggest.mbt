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
fn generate_candidates(
  dictionary : Dictionary,
  config : AffixConfig,
) -> Array[String] {
  let candidates : Array[String] = []
  for entry in dictionary.entries {
    if entry_is_forbidden(config, entry) ||
      entry_is_nosuggest(config, entry) ||
      entry.word.contains(" ") {
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
        if prefix.cross_product &&
          suffix.cross_product &&
          flags_contain(config, entry.flags, prefix.flag) &&
          flags_contain(config, entry.flags, suffix.flag) &&
          condition_matches(prefix, entry.word) &&
          condition_matches(suffix, entry.word) {
          match remove_prefix_strip(entry.word, prefix.strip) {
            Some(without_prefix) =>
              match remove_suffix_strip(without_prefix, suffix.strip) {
                Some(base) =>
                  remember_unique(candidates, prefix.add + base + suffix.add)
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
      let substitution = previous[j - 1] +
        (if a[i - 1] == b[j - 1] { 0 } else { 1 })
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
fn insert_ranked(
  result : Array[Suggestion],
  candidate : Suggestion,
  limit : Int,
) -> Unit {
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
    let lower = language_lower(config, word)
    for entry in dictionary.entries {
      if language_lower(config, entry.word) == lower &&
        !entry_is_forbidden(config, entry) {
        return true
      }
    }
    for part in word.split(" ") {
      let token = part.to_owned()
      if token.is_empty() {
        return false
      }
      let result = spell(dictionary, config, token)
      if !result.accepted || result.stem is None {
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
fn find_from(text : String, needle : String, start : Int) -> Int? {
  if start > text.length() || needle.is_empty() {
    return None
  }
  match text.view(start_offset=start).find(needle) {
    Some(index) => Some(start + index)
    None => None
  }
}

///|
fn replace_at(
  text : String,
  start : Int,
  length : Int,
  replacement : String,
) -> String {
  text.view(end_offset=start).to_owned() +
  replacement +
  text.view(start_offset=start + length).to_owned()
}

///|
fn replace_occurrences(
  text : String,
  from : String,
  to : String,
) -> Array[String] {
  let result : Array[String] = []
  if from.is_empty() {
    return result
  }
  let mut offset = 0
  while offset <= text.length() {
    match find_from(text, from, offset) {
      Some(index) => {
        let candidate = replace_at(text, index, from.length(), to)
        if candidate != text && !result.contains(candidate) {
          result.push(candidate)
        }
        offset = index + 1
      }
      None => break
    }
  }
  result
}

///|
fn drop_last_char(text : String) -> String {
  let chars = text.to_array()
  if chars.length() == 0 {
    text
  } else {
    String::from_array(chars.exact_view(end=chars.length() - 1))
  }
}

///|
fn capitalize_first(text : String) -> String {
  let chars = text.to_array()
  if chars.length() == 0 {
    text
  } else {
    chars[0].to_string().to_upper() +
    String::from_array(chars.exact_view(start=1))
  }
}

///|
fn ph_entry_rules(entry : DicEntry) -> Array[ReplacementRule] {
  let result : Array[ReplacementRule] = []
  let fields = entry.morph.replace_all(old="\t", new=" ").split(" ")
  for raw_field in fields {
    let field = raw_field.trim().to_owned()
    if field.find("ph:") != Some(0) || field.length() <= 3 {
      continue
    }
    let payload = field.view(start_offset=3).to_owned()
    if payload.is_empty() {
      continue
    }
    let rule_pair = match payload.split_once("->") {
      Some((left, right)) => {
        let from = left.to_owned()
        let to = right.to_owned()
        if from.is_empty() || to.is_empty() {
          (payload, entry.word)
        } else {
          (from, to)
        }
      }
      None => (payload, entry.word)
    }
    let mut pattern = rule_pair.0
    let mut replacement = rule_pair.1
    if ends_with(pattern.view(), "*") {
      pattern = drop_last_char(pattern)
      replacement = drop_last_char(replacement)
    }
    if pattern.is_empty() || replacement.is_empty() {
      continue
    }
    result.push({ from: pattern, to: replacement, })
  }
  result
}

///|
fn ph_candidates(word : String, dictionary : Dictionary) -> Array[String] {
  let result : Array[String] = []
  for entry in dictionary.entries {
    for rule in ph_entry_rules(entry) {
      let variants : Array[(String, String)] = [(rule.from, rule.to)]
      if is_capitalized(word) && !is_capitalized(rule.from) {
        variants.push((capitalize_first(rule.from), rule.to))
      }
      if is_all_upper(word) {
        variants.push((rule.from.to_upper(), rule.to.to_upper()))
      }
      for pair in variants {
        let (from, to) = pair
        for candidate in replace_occurrences(word, from, to) {
          remember_unique(result, candidate)
        }
      }
    }
  }
  result
}

///|
fn exact_word_pair_candidate(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> String? {
  let chars = word.to_array()
  let mut index = 1
  while index < chars.length() {
    let left = String::from_array(chars.exact_view(end=index))
    let right = String::from_array(chars.exact_view(start=index))
    for separator in [" ", "-"] {
      let candidate = left + separator + right
      for entry in dictionary.find_entries(candidate) {
        if entry_can_be_exact(config, entry) {
          return Some(candidate)
        }
      }
    }
    index += 1
  }
  None
}

///|
fn word_pair_candidates(
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
) -> Array[String] {
  let result : Array[String] = []
  match exact_word_pair_candidate(dictionary, config, word) {
    Some(candidate) => {
      result.push(candidate)
      return result
    }
    None => ()
  }
  let chars = word.to_array()
  let mut index = 1
  while index < chars.length() {
    let left = String::from_array(chars.exact_view(end=index))
    let right = String::from_array(chars.exact_view(start=index))
    let left_result = spell(dictionary, config, left)
    let right_result = spell(dictionary, config, right)
    if !left.is_empty() &&
      !right.is_empty() &&
      left_result.accepted &&
      left_result.stem is Some(_) &&
      right_result.accepted &&
      right_result.stem is Some(_) {
      remember_unique(result, left + " " + right)
      remember_unique(result, left + "-" + right)
    }
    index += 1
  }
  result
}

///|
fn double_two_candidates(word : String) -> Array[String] {
  let result : Array[String] = []
  let chars = word.to_array()
  if chars.length() < 5 {
    return result
  }
  let mut state = 0
  for i in 2..<chars.length() {
    if chars[i] == chars[i - 2] {
      state += 1
      if state == 3 || (state == 2 && i >= 4) {
        let candidate = String::from_array(chars.exact_view(end=i - 1)) +
          String::from_array(chars.exact_view(start=i + 1))
        remember_unique(result, candidate)
        state = 0
      }
    } else {
      state = 0
    }
  }
  result
}

///|
fn add_direct_suggestions(
  result : Array[Suggestion],
  candidates : Array[String],
  limit : Int,
) -> Unit {
  for candidate in candidates {
    if result.length() >= limit {
      return
    }
    if !result.any(item => item.word == candidate) {
      result.push({ word: candidate, distance: 0, })
    }
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
            result.push(
              word.view(end_offset=i).to_owned() +
              chars[j - 1].to_string() +
              word.view(start_offset=i + 1).to_owned(),
            )
          }
          if j + 1 < chars.length() {
            result.push(
              word.view(end_offset=i).to_owned() +
              chars[j + 1].to_string() +
              word.view(start_offset=i + 1).to_owned(),
            )
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
        result.push(
          mapping.view(start_offset=index + 1, end_offset=close).to_owned(),
        )
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
fn try_candidates(
  word : String,
  config : AffixConfig,
  limit : Int,
) -> Array[String] {
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
fn char_at_or_nul(chars : Array[Char], index : Int) -> Char {
  if index >= 0 && index < chars.length() {
    chars[index]
  } else {
    '\u{0}'
  }
}

///|
fn ngram_score(
  n : Int,
  left : Array[Char],
  right : Array[Char],
  longer_worse : Bool,
  any_mismatch : Bool,
  weighted : Bool,
) -> Int {
  let mut nscore = 0
  let l1 = left.length()
  let l2 = right.length()
  if l2 == 0 {
    return 0
  }
  let mut width = 1
  while width <= n {
    let mut ns = 0
    if l1 >= width {
      for i in 0..<=(l1 - width) {
        let mut found = false
        if l2 >= width {
          for j in 0..<=(l2 - width) {
            let mut equal = true
            for k in 0..<width {
              if left[i + k] != right[j + k] {
                equal = false
                break
              }
            }
            if equal {
              found = true
              break
            }
          }
        }
        if found {
          ns += 1
        } else if weighted {
          ns -= 1
          if i == 0 || i == l1 - width {
            ns -= 1
          }
        }
      }
    }
    nscore += ns
    if ns < 2 && !weighted {
      break
    }
    width += 1
  }
  let mut penalty = 0
  if longer_worse {
    penalty = l2 - l1 - 2
  }
  if any_mismatch {
    penalty = (l2 - l1).abs() - 2
  }
  nscore - (if penalty > 0 { penalty } else { 0 })
}

///|
fn left_common_substring(left : Array[Char], right : Array[Char]) -> Int {
  if left.length() == 0 || right.length() == 0 {
    return 0
  }
  let lower_first = right[0].to_string().to_lower()
  if left[0] != right[0] && left[0].to_string() != lower_first {
    return 0
  }
  let mut index = 1
  while index < left.length() &&
        index < right.length() &&
        left[index] == right[index] {
    index += 1
  }
  index
}

///|
fn lcs_length(left : Array[Char], right : Array[Char]) -> Int {
  if left.length() == 0 || right.length() == 0 {
    return 0
  }
  let mut previous = Array::make(right.length() + 1, 0)
  for i in 1..<=left.length() {
    let current = Array::make(right.length() + 1, 0)
    for j in 1..<=right.length() {
      if left[i - 1] == right[j - 1] {
        current[j] = previous[j - 1] + 1
      } else {
        current[j] = if current[j - 1] >= previous[j] {
          current[j - 1]
        } else {
          previous[j]
        }
      }
    }
    previous = current
  }
  previous[right.length()]
}

///|
fn ngram_rank(word : String, candidate : String, config : AffixConfig) -> Int {
  let left = language_lower(config, word).to_array()
  let right = language_lower(config, candidate).to_array()
  let lcs = lcs_length(left, right)
  let left_common = left_common_substring(left, right)
  let quad = ngram_score(4, left, right, false, true, false)
  let forward = ngram_score(2, left, right, false, true, true)
  let reverse = ngram_score(2, right, left, false, true, true)
  let mut score = 2 * lcs -
    (left.length() - right.length()).abs() +
    left_common +
    quad +
    forward +
    reverse
  if left.length() == right.length() && left == right {
    score += 2000
  }
  score
}

///|
fn entry_phonetic_fields(entry : DicEntry) -> Array[String] {
  let result : Array[String] = []
  let fields = entry.morph.replace_all(old="\t", new=" ").split(" ")
  for raw_field in fields {
    let field = raw_field.trim().to_owned()
    if field.find("ph:") == Some(0) && field.length() > 3 {
      let value = field.view(start_offset=3).to_owned()
      if !value.is_empty() && value != "ph:" {
        result.push(value)
      }
    }
  }
  result
}

///|
priv struct RankedCandidate {
  word : String
  score : Int
}

///|
fn insert_ranked_candidate(
  candidates : Array[RankedCandidate],
  word : String,
  score : Int,
) -> Unit {
  for i in 0..<candidates.length() {
    if candidates[i].word == word {
      if score > candidates[i].score {
        ignore(candidates.remove(i))
        insert_ranked_candidate(candidates, word, score)
      }
      return
    }
  }
  let mut inserted = false
  for i in 0..<candidates.length() {
    if score > candidates[i].score {
      candidates.insert(i, { word, score, })
      inserted = true
      break
    }
  }
  if !inserted {
    candidates.push({ word, score, })
  }
}

///|
fn phone_char_at(chars : Array[Char], index : Int) -> Char {
  char_at_or_nul(chars, index)
}

///|
fn phone_is_alpha(ch : Char) -> Bool {
  let code = ch.to_int()
  code >= 128 || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
}

///|
fn phone_contains(text : StringView, ch : Char) -> Bool {
  for item in text {
    if item == ch {
      return true
    }
  }
  false
}

///|
fn phonet(text : String, rules : Array[PhoneRule]) -> String {
  let word = text.to_upper().to_array()
  let target : Array[Char] = []
  let length = word.length()
  let mut index = 0
  while index < word.length() {
    let actual = word[index]
    let mut z0 = false
    let mut k = 0
    let mut p0 = -333
    let mut tail_char = actual
    for rule in rules {
      let pattern = rule.pattern.to_array()
      if pattern.length() == 0 || pattern[0] != actual {
        continue
      }
      k = 1
      let mut pattern_index = 1
      while pattern_index < pattern.length() &&
            phone_is_alpha(phone_char_at(pattern, pattern_index)) &&
            phone_char_at(pattern, pattern_index) != '(' &&
            phone_char_at(pattern, pattern_index) != '-' &&
            phone_char_at(pattern, pattern_index) != '<' &&
            phone_char_at(pattern, pattern_index) != '^' &&
            phone_char_at(pattern, pattern_index) != '$' &&
            phone_char_at(word, index + k) ==
            phone_char_at(pattern, pattern_index) {
        k += 1
        pattern_index += 1
      }
      if phone_char_at(pattern, pattern_index) == '(' {
        if phone_is_alpha(phone_char_at(word, index + k)) &&
          phone_contains(
            rule.pattern.view(start_offset=pattern_index + 1),
            phone_char_at(word, index + k),
          ) {
          k += 1
          while pattern_index < pattern.length() &&
                phone_char_at(pattern, pattern_index) != ')' {
            pattern_index += 1
          }
          if pattern_index < pattern.length() {
            pattern_index += 1
          }
        }
      }
      p0 = phone_char_at(pattern, pattern_index).to_int()
      let k0 = k
      while phone_char_at(pattern, pattern_index) == '-' && k > 1 {
        k -= 1
        pattern_index += 1
      }
      if phone_char_at(pattern, pattern_index) == '<' {
        pattern_index += 1
      }
      if phone_char_at(pattern, pattern_index).is_ascii_digit() {
        pattern_index += 1
      }
      if phone_char_at(pattern, pattern_index) == '^' &&
        phone_char_at(pattern, pattern_index + 1) == '^' {
        pattern_index += 1
      }
      let current = phone_char_at(pattern, pattern_index)
      let anchored_start = current == '^' &&
        (index == 0 || !phone_is_alpha(phone_char_at(word, index - 1))) &&
        (
          phone_char_at(pattern, pattern_index + 1) != '$' ||
          !phone_is_alpha(phone_char_at(word, index + k0))
        )
      let anchored_end = current == '$' &&
        index > 0 &&
        phone_is_alpha(phone_char_at(word, index - 1)) &&
        !phone_is_alpha(phone_char_at(word, index + k0))
      if current != '\u{0}' && !anchored_start && !anchored_end {
        continue
      }
      let replacement = rule.replacement.to_array()
      if rule.pattern.contains("<") {
        if target.length() > 0 &&
          replacement.length() > 0 &&
          (
            target[target.length() - 1] == actual ||
            target[target.length() - 1] == replacement[0]
          ) {
          ignore(target.pop())
        }
        z0 = true
      } else {
        index += k - 1
        for replacement_index in 0..<replacement.length() {
          let ch = replacement[replacement_index]
          if replacement_index + 1 < replacement.length() &&
            target.length() < length {
            if target.length() == 0 || target[target.length() - 1] != ch {
              target.push(ch)
            }
          }
        }
        tail_char = if replacement.length() > 0 {
          replacement[replacement.length() - 1]
        } else {
          '\u{0}'
        }
      }
      break
    }
    if !z0 {
      if k > 0 && p0 == 0 && target.length() < length && tail_char != '\u{0}' {
        target.push(tail_char)
      }
      index += 1
    }
  }
  String::from_iter(target.iter())
}

///|
fn phonetic_candidate_score(
  word : String,
  candidate : String,
  config : AffixConfig,
) -> Int {
  if config.phone_rules.length() == 0 {
    return -20000
  }
  let target = phonet(word, config.phone_rules)
  let candidate_phone = phonet(candidate, config.phone_rules)
  let score = 2 *
    ngram_score(
      3,
      target.to_array(),
      candidate_phone.to_array(),
      true,
      false,
      false,
    )
  let left = language_lower(config, word).to_array()
  let right = language_lower(config, candidate).to_array()
  score +
  2 * lcs_length(left, right) -
  (left.length() - right.length()).abs() +
  left_common_substring(left, right)
}

///|
fn common_prefix_length(left : String, right : String) -> Int {
  let a = left.to_array()
  let b = right.to_array()
  let mut index = 0
  while index < a.length() && index < b.length() && a[index] == b[index] {
    index += 1
  }
  index
}

///|
fn add_phone_suggestions(
  result : Array[Suggestion],
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
  limit : Int,
) -> Unit {
  if config.phone_rules.length() == 0 || result.length() >= limit {
    return
  }
  let text_candidates : Array[RankedCandidate] = []
  let phone_candidates : Array[RankedCandidate] = []
  for entry in dictionary.entries {
    if entry_is_forbidden(config, entry) || entry_is_nosuggest(config, entry) {
      continue
    }
    insert_ranked_candidate(
      text_candidates,
      entry.word,
      ngram_rank(word, entry.word, config) * 100 -
      phonetic_candidate_score(word, entry.word, config),
    )
    insert_ranked_candidate(
      phone_candidates,
      entry.word,
      phonetic_candidate_score(word, entry.word, config),
    )
    for field in entry_phonetic_fields(entry) {
      insert_ranked_candidate(
        text_candidates,
        entry.word,
        ngram_rank(word, field, config) * 100 -
        phonetic_candidate_score(word, entry.word, config) -
        100,
      )
    }
  }
  let best_text = if text_candidates.length() > 0 {
    text_candidates[0].score
  } else {
    0
  }
  for item in text_candidates {
    if result.length() >= limit {
      return
    }
    let too_similar = result.any(existing => {
      let prefix = common_prefix_length(
        existing.word.to_lower(),
        item.word.to_lower(),
      )
      prefix >= 7 && prefix < item.word.length()
    })
    if item.score >= best_text - 1100 &&
      !too_similar &&
      suggestion_word_is_valid(dictionary, config, item.word) {
      let output = if is_capitalized(word) && !is_all_upper(word) {
        capitalize_first(item.word)
      } else {
        item.word
      }
      result.push({
        word: output,
        distance: levenshtein_distance(word, item.word),
      })
    }
  }
  let mut added_phone = 0
  for item in phone_candidates {
    if result.length() >= limit || added_phone >= 4 {
      break
    }
    let output = if is_capitalized(word) && !is_all_upper(word) {
      capitalize_first(item.word)
    } else {
      item.word
    }
    let duplicate = result.any(existing => {
      language_lower(config, existing.word) == language_lower(config, output)
    })
    if !duplicate && suggestion_word_is_valid(dictionary, config, item.word) {
      result.push({
        word: output,
        distance: levenshtein_distance(word, item.word),
      })
      added_phone += 1
    }
  }
}

///|
fn add_ngram_suggestions(
  result : Array[Suggestion],
  dictionary : Dictionary,
  config : AffixConfig,
  word : String,
  limit : Int,
) -> Unit {
  if config.max_ngram_sugs == 0 || result.length() >= limit {
    return
  }
  let ranked : Array[RankedCandidate] = []
  for entry in dictionary.entries {
    if entry_is_forbidden(config, entry) || entry_is_nosuggest(config, entry) {
      continue
    }
    if entry.word != word {
      let mut score = ngram_rank(word, entry.word, config) + 8
      for field in entry_phonetic_fields(entry) {
        let field_score = ngram_rank(word, field, config)
        if field_score > score {
          score = field_score
        }
      }
      insert_ranked_candidate(ranked, entry.word, score)
    }
  }
  for candidate in generate_candidates(dictionary, config) {
    if candidate != word &&
      suggestion_word_is_valid(dictionary, config, candidate) {
      insert_ranked_candidate(
        ranked,
        candidate,
        ngram_rank(word, candidate, config),
      )
    }
  }
  let mut added = 0
  for item in ranked {
    if added >= config.max_ngram_sugs || result.length() >= limit {
      break
    }
    if !result.any(existing => existing.word == item.word) {
      result.push({
        word: item.word,
        distance: levenshtein_distance(word, item.word),
      })
      added += 1
    }
  }
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
  add_phone_suggestions(result, dictionary, config, word, limit)
  if config.phone_rules.length() > 0 && result.length() > 0 {
    return result
  }
  add_direct_suggestions(
    result,
    word_pair_candidates(dictionary, config, word),
    limit,
  )
  add_rule_suggestions(
    result,
    dictionary,
    config,
    case_candidates(dictionary, config, word),
    limit,
  )
  add_rule_suggestions(
    result,
    dictionary,
    config,
    key_candidates(word, config),
    limit,
  )
  add_rule_suggestions(
    result,
    dictionary,
    config,
    rep_candidates(word, config),
    limit,
  )
  add_rule_suggestions(
    result,
    dictionary,
    config,
    ph_candidates(word, dictionary),
    limit,
  )
  add_rule_suggestions(
    result,
    dictionary,
    config,
    map_candidates(word, config),
    limit,
  )
  add_rule_suggestions(
    result,
    dictionary,
    config,
    double_two_candidates(word),
    limit,
  )
  if result.length() == 0 {
    add_ngram_suggestions(result, dictionary, config, word, limit)
  }
  add_rule_suggestions(
    result,
    dictionary,
    config,
    try_candidates(word, config, limit * 200),
    limit,
  )
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
