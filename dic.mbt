///|
pub(all) struct DicEntry {
  word : String
  flags : String
  morph : String
}

///|
pub(all) struct Dictionary {
  declared_count : Int
  entries : Array[DicEntry]
}

///|
pub suberror DicParseError {
  EmptyDictionary
  InvalidHeader(String)
}

///|
fn parse_decimal_count(text : String) -> Int? {
  let value = text.trim()
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for c in value {
    if !c.is_ascii_digit() {
      return None
    }
    result = result * 10 + c.to_int() - '0'.to_int()
  }
  Some(result)
}

///|
fn split_at_first_space(text : StringView) -> (String, String) {
  match text.find_by(c => c.is_whitespace()) {
    Some(index) =>
      (
        text.view(end_offset=index).to_owned(),
        text.view(start_offset=index + 1).trim().to_owned(),
      )
    None => (text.trim().to_owned(), "")
  }
}

///|
pub fn parse_dic_entry(line : String) -> DicEntry? {
  let value = line.trim().replace_all(old="\\/", new="\u{FDE1}")
  if value == "/" {
    return Some({ word: "/", flags: "", morph: "", })
  }
  if value == "/" {
    return Some({ word: "/", flags: "", morph: "", })
  }
  if value.is_empty() {
    return None
  }
  match value.split_once("/") {
    Some((word, suffix)) => {
      if word.is_empty() {
        return None
      }
      let (flags, morph) = split_at_first_space(suffix)
      Some({ word: word.to_owned().replace_all(old="\u{FDE1}", new="/"), flags, morph, })
    }
    None => {
      match value.find("\t") {
        Some(index) => {
          let word = value.view(end_offset=index).trim().to_owned()
          let morph = value.view(start_offset=index + 1).trim().to_owned()
          if word.is_empty() { None } else { Some({ word: word.replace_all(old="\u{FDE1}", new="/"), flags: "", morph, }) }
        }
        None => Some({ word: value.replace_all(old="\u{FDE1}", new="/").to_owned(), flags: "", morph: "", })
      }
    }
  }
}

///|
pub fn parse_dic(text : String) -> Result[Dictionary, DicParseError] {
  let lines = strip_bom(text).split("\n").collect()
  let mut header_index = -1
  let mut header = ""
  for i in 0..<lines.length() {
    let line = lines[i].trim().to_owned()
    if !line.is_empty() {
      header_index = i
      header = line
      break
    }
  }
  if header_index < 0 {
    return Err(EmptyDictionary)
  }
  let declared_count = match parse_decimal_count(header) {
    Some(count) => count
    None => return Err(InvalidHeader(header))
  }
  let entries : Array[DicEntry] = []
  for i in (header_index + 1)..<lines.length() {
    match parse_dic_entry(lines[i].to_owned()) {
      Some(entry) => entries.push(entry)
      None => ()
    }
  }
  Ok({ declared_count, entries, })
}

///|
pub fn Dictionary::has_word(self : Dictionary, word : String) -> Bool {
  let mut found = false
  for entry in self.entries {
    if entry.word == word {
      found = true
      break
    }
  }
  found
}
