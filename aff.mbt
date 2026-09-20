///|
pub(all) enum AffixKind {
  Prefix
  Suffix
} derive(Eq)

///|
pub(all) struct AffixRule {
  kind : AffixKind
  flag : String
  cross_product : Bool
  strip : String
  add : String
  continuation : String
  condition : String
}

///|
pub(all) struct ReplacementRule {
  from : String
  to : String
}

///|
pub(all) struct AffixConfig {
  encoding : String
  flag_mode : String
  try_chars : String
  word_chars : String
  flag_aliases : Array[String]
  morph_aliases : Array[String]
  prefixes : Array[AffixRule]
  suffixes : Array[AffixRule]
  replacements : Array[ReplacementRule]
  maps : Array[String]
  forbidden_word : String?
  keep_case : String?
  need_affix : String?
  circumfix : String?
  unsupported : Array[String]
}

///|
pub suberror AffixParseError {
  InvalidAffixHeader(Int, String)
  InvalidAffixRule(Int, String)
}

///|
fn tokenize_aff_line(line : String) -> Array[String] {
  line.replace_all(old="\t", new=" ").split(" ").filter(token => token.length() > 0).map(token => token.to_owned()).collect()
}

///|
fn normalize_affix_text(text : String) -> String {
  if text == "0" {
    ""
  } else {
    text
  }
}

///|
fn parse_affix_rule(
  line_number : Int,
  tokens : Array[String],
  kind : AffixKind,
  flag : String,
  cross_product : Bool,
) -> Result[AffixRule, AffixParseError] {
  if tokens.length() < 4 {
    return Err(InvalidAffixRule(line_number, tokens.join(" ")))
  }
  let condition = if tokens.length() >= 5 {
    tokens[4]
  } else {
    "."
  }
  let (add, continuation) = match tokens[3].split_once("/") {
    Some((add, flags)) => (normalize_affix_text(add.to_owned()), flags.to_owned())
    None => (normalize_affix_text(tokens[3]), "")
  }
  Ok({
    kind,
    flag,
    cross_product,
    strip: normalize_affix_text(tokens[2]),
    add,
    continuation,
    condition,
  })
}

///|
pub fn parse_aff(text : String) -> Result[AffixConfig, AffixParseError] {
  let lines = strip_bom(text).split("\n").collect()
  let mut encoding = "ISO8859-1"
  let mut flag_mode = "char"
  let mut try_chars = ""
  let mut word_chars = ""
  let flag_aliases : Array[String] = []
  let morph_aliases : Array[String] = []
  let prefixes : Array[AffixRule] = []
  let suffixes : Array[AffixRule] = []
  let replacements : Array[ReplacementRule] = []
  let maps : Array[String] = []
  let mut forbidden_word : String? = None
  let mut keep_case : String? = None
  let mut need_affix : String? = None
  let mut circumfix : String? = None
  let unsupported : Array[String] = []
  let mut current_kind = AffixKind::Prefix
  let mut current_flag = ""
  let mut current_cross_product = false
  let mut have_affix_header = false
  for i in 0..<lines.length() {
    let raw = lines[i].trim().to_owned()
    if raw.is_empty() || raw.find("#") == Some(0) {
      continue
    }
    let tokens = tokenize_aff_line(raw)
    if tokens.length() == 0 {
      continue
    }
    let directive = tokens[0]
    match directive {
      "SET" => {
        if tokens.length() >= 2 {
          encoding = tokens[1]
        }
      }
      "FLAG" => {
        if tokens.length() >= 2 {
          flag_mode = tokens[1]
        }
      }
      "TRY" => {
        if tokens.length() >= 2 {
          try_chars = tokens[1]
        }
      }
      "WORDCHARS" => {
        if tokens.length() >= 2 {
          word_chars = tokens[1]
        }
      }
      "FORBIDDENWORD" => {
        if tokens.length() >= 2 {
          forbidden_word = Some(tokens[1])
        }
      }
      "KEEPCASE" => {
        if tokens.length() >= 2 {
          keep_case = Some(tokens[1])
        }
      }
      "NEEDAFFIX" => {
        if tokens.length() >= 2 {
          need_affix = Some(tokens[1])
        }
      }
      "CIRCUMFIX" => {
        if tokens.length() >= 2 {
          circumfix = Some(tokens[1])
        }
      }
      "AF" => {
        if tokens.length() >= 2 {
          match parse_decimal_count(tokens[1]) {
            Some(_) => ()
            None => flag_aliases.push(tokens[1])
          }
        }
      }
      "AM" => {
        if tokens.length() >= 2 {
          match parse_decimal_count(tokens[1]) {
            Some(_) => ()
            None => morph_aliases.push(tokens[1])
          }
        }
      }
      "PFX" | "SFX" => {
        if tokens.length() < 2 {
          return Err(InvalidAffixHeader(i + 1, raw))
        }
        let kind = if directive == "PFX" {
          AffixKind::Prefix
        } else {
          AffixKind::Suffix
        }
        if tokens.length() == 4 && (tokens[2] == "Y" || tokens[2] == "N") {
          current_kind = kind
          current_flag = tokens[1]
          current_cross_product = tokens[2] == "Y"
          have_affix_header = true
        } else {
          let flag = if have_affix_header && current_kind == kind {
            current_flag
          } else {
            tokens[1]
          }
          let cross_product = if have_affix_header && current_kind == kind {
            current_cross_product
          } else {
            false
          }
          match parse_affix_rule(i + 1, tokens, kind, flag, cross_product) {
            Ok(rule) =>
              match kind {
                Prefix => prefixes.push(rule)
                Suffix => suffixes.push(rule)
              }
            Err(error) => return Err(error)
          }
        }
      }
      "REP" => {
        if tokens.length() >= 3 {
          replacements.push({ from: tokens[1], to: tokens[2], })
        }
      }
      "MAP" => {
        if tokens.length() >= 2 {
          match parse_decimal_count(tokens[1]) {
            Some(_) => ()
            None => maps.push(tokens[1])
          }
        }
      }
      _ => unsupported.push(directive)
    }
  }
  Ok({
    encoding,
    flag_mode,
    try_chars,
    word_chars,
    flag_aliases,
    morph_aliases,
    prefixes,
    suffixes,
    replacements,
    maps,
    forbidden_word,
    keep_case,
    need_affix,
    circumfix,
    unsupported,
  })
}