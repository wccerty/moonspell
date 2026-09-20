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
pub(all) struct CompoundPattern {
  end_chars : String
  end_flag : String?
  end_zero : Bool
  begin_chars : String
  begin_flag : String?
  replacement : String?
}
///|
pub(all) struct AffixConfig {
  encoding : String
  language : String
  ignore_chars : String
  break_enabled : Bool
  break_explicit : Bool
  break_patterns : Array[String]
  flag_mode : String
  try_chars : String
  keyboard : String
  word_chars : String
  flag_aliases : Array[String]
  morph_aliases : Array[String]
  prefixes : Array[AffixRule]
  suffixes : Array[AffixRule]
  replacements : Array[ReplacementRule]
  iconv_rules : Array[ReplacementRule]
  oconv_rules : Array[ReplacementRule]
  maps : Array[String]
  forbidden_word : String?
  keep_case : String?
  need_affix : String?
  no_suggest : String?
  circumfix : String?
  complex_prefixes : Bool
  check_sharps : Bool
  compound_min : Int
  compound_word_max : Int
  compound_flag : String?
  compound_begin : String?
  compound_middle : String?
  compound_end : String?
  compound_permit : String?
  compound_forbid : String?
  only_in_compound : String?
  check_compound_dup : Bool
  check_compound_rep : Bool
  check_compound_case : Bool
  check_compound_triple : Bool
  compound_rules : Array[String]
  compound_patterns : Array[CompoundPattern]
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
  let mut language = ""
  let mut ignore_chars = ""
  let mut break_enabled = true
  let mut break_explicit = false
  let break_patterns : Array[String] = ["-", "–"]
  let mut flag_mode = "char"
  let mut try_chars = ""
  let mut keyboard = ""
  let mut word_chars = ""
  let flag_aliases : Array[String] = []
  let morph_aliases : Array[String] = []
  let prefixes : Array[AffixRule] = []
  let suffixes : Array[AffixRule] = []
  let replacements : Array[ReplacementRule] = []
  let iconv_rules : Array[ReplacementRule] = []
  let oconv_rules : Array[ReplacementRule] = []
  let maps : Array[String] = []
  let mut forbidden_word : String? = None
  let mut keep_case : String? = None
  let mut need_affix : String? = None
  let mut no_suggest : String? = None
  let mut circumfix : String? = None
  let mut complex_prefixes = false
  let mut check_sharps = false
  let mut compound_min = 3
  let mut compound_word_max = 0
  let mut compound_flag : String? = None
  let mut compound_begin : String? = None
  let mut compound_middle : String? = None
  let mut compound_end : String? = None
  let mut compound_permit : String? = None
  let mut compound_forbid : String? = None
  let mut only_in_compound : String? = None
  let mut check_compound_dup = false
  let mut check_compound_rep = false
  let mut check_compound_case = false
  let mut check_compound_triple = false
  let compound_rules : Array[String] = []
  let compound_patterns : Array[CompoundPattern] = []
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
      "COMPLEXPREFIXES" => complex_prefixes = true
      "CHECKSHARPS" => check_sharps = true
      "IGNORE" => {
        if tokens.length() >= 2 { ignore_chars = tokens[1] }
      }
      "BREAK" => {
        if tokens.length() >= 2 {
          break_explicit = true
          match parse_decimal_count(tokens[1]) {
            Some(0) => {
              break_enabled = false
              break_patterns.clear()
            }
            Some(_) => {
              break_enabled = true
              break_patterns.clear()
            }
            None => {
              break_enabled = true
              break_patterns.push(tokens[1])
            }
          }
        }
      }
      "LANG" => {
        if tokens.length() >= 2 { language = tokens[1] }
      }
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
      "KEY" => {
        if tokens.length() >= 2 { keyboard = tokens[1] }
      }
      "NOSUGGEST" => {
        if tokens.length() >= 2 { no_suggest = Some(tokens[1]) }
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
      "COMPOUNDMIN" => {
        if tokens.length() >= 2 {
          match parse_decimal_count(tokens[1]) {
            Some(value) => compound_min = value
            None => ()
          }
        }
      }
      "COMPOUNDWORDMAX" => {
        if tokens.length() >= 2 {
          match parse_decimal_count(tokens[1]) {
            Some(value) => compound_word_max = value
            None => ()
          }
        }
      }
      "COMPOUNDFLAG" => {
        if tokens.length() >= 2 { compound_flag = Some(tokens[1]) }
      }
      "COMPOUNDBEGIN" => {
        if tokens.length() >= 2 { compound_begin = Some(tokens[1]) }
      }
      "COMPOUNDMIDDLE" => {
        if tokens.length() >= 2 { compound_middle = Some(tokens[1]) }
      }
      "COMPOUNDEND" => {
        if tokens.length() >= 2 { compound_end = Some(tokens[1]) }
      }
      "COMPOUNDPERMITFLAG" => {
        if tokens.length() >= 2 { compound_permit = Some(tokens[1]) }
      }
      "COMPOUNDFORBIDFLAG" => {
        if tokens.length() >= 2 { compound_forbid = Some(tokens[1]) }
      }
      "ONLYINCOMPOUND" => {
        if tokens.length() >= 2 { only_in_compound = Some(tokens[1]) }
      }
      "CHECKCOMPOUNDDUP" => check_compound_dup = true
      "CHECKCOMPOUNDREP" => check_compound_rep = true
      "CHECKCOMPOUNDCASE" => check_compound_case = true
      "CHECKCOMPOUNDTRIPLE" => check_compound_triple = true
      "COMPOUNDRULE" => {
        if tokens.length() >= 2 {
          match parse_decimal_count(tokens[1]) {
            Some(_) => ()
            None => compound_rules.push(tokens[1])
          }
        }
      }
      "CHECKCOMPOUNDPATTERN" => {
        if tokens.length() >= 3 {
          match parse_decimal_count(tokens[1]) {
            Some(_) => if tokens.length() == 2 { () }
            None => {
              let (end_chars_raw, end_flag) = match tokens[1].split_once("/") {
                Some((chars, flag)) => (chars.to_owned(), Some(flag.to_owned()))
                None => (tokens[1], None)
              }
              let (begin_chars_raw, begin_flag) = match tokens[2].split_once("/") {
                Some((chars, flag)) => (chars.to_owned(), Some(flag.to_owned()))
                None => (tokens[2], None)
              }
              let end_zero = end_chars_raw == "0"
              let end_chars = if end_zero { "" } else { end_chars_raw }
              let begin_chars = if begin_chars_raw == "0" { "" } else { begin_chars_raw }
              let replacement = if tokens.length() >= 4 { Some(tokens[3]) } else { None }
              compound_patterns.push({
                end_chars,
                end_flag,
                end_zero,
                begin_chars,
                begin_flag,
                replacement,
              })
            }
          }
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
      "ICONV" => {
        if tokens.length() >= 3 {
          iconv_rules.push({ from: tokens[1], to: tokens[2], })
        }
      }
      "OCONV" => {
        if tokens.length() >= 3 {
          oconv_rules.push({ from: tokens[1], to: tokens[2], })
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
    language,
    ignore_chars,
    break_enabled,
    break_explicit,
    break_patterns,
    flag_mode,
    try_chars,
    keyboard,
    word_chars,
    flag_aliases,
    morph_aliases,
    prefixes,
    suffixes,
    replacements,
    iconv_rules,
    oconv_rules,
    maps,
    forbidden_word,
    keep_case,
    need_affix,
    no_suggest,
    circumfix,
    complex_prefixes,
    check_sharps,
    compound_min,
    compound_word_max,
    compound_flag,
    compound_begin,
    compound_middle,
    compound_end,
    compound_permit,
    compound_forbid,
    only_in_compound,
    check_compound_dup,
    check_compound_rep,
    check_compound_case,
    check_compound_triple,
    compound_rules,
    compound_patterns,
    unsupported,
  })
}