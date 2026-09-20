///|
fn usage() -> Unit {
  println("MoonSpell " + @lib.version())
  println("Usage:")
  println("  moonspell validate <aff> <dic>")
  println("  moonspell check <aff> <dic> <word>...")
  println("  moonspell suggest <aff> <dic> <word> [--limit N]")
  println("  moonspell check-file <aff> <dic> <word-file>")
  println("  moonspell suggest-file <aff> <dic> <word-file> [--limit N]")
}

///|
fn read_file(path : String) -> String? {
  try {
    Some(@lib.strip_bom(@fs.read_file_to_string(path)))
  } catch {
    _ => None
  }
}

///|
fn parse_limit(args : Array[String]) -> Int {
  for i in 5..<args.length() {
    if args[i] == "--limit" && i + 1 < args.length() {
      let digits = args[i + 1]
      if digits.is_empty() {
        return 5
      }
      let mut value = 0
      for c in digits {
        if !c.is_ascii_digit() {
          return 5
        }
        value = value * 10 + c.to_int() - '0'.to_int()
      }
      return value
    }
  }
  5
}

///|
fn load(aff_path : String, dic_path : String) -> (@lib.AffixConfig, @lib.Dictionary)? {
  let aff_text = match read_file(aff_path) {
    Some(text) => text
    None => {
      println("Failed to read affix file: " + aff_path)
      return None
    }
  }
  let dic_text = match read_file(dic_path) {
    Some(text) => text
    None => {
      println("Failed to read dictionary file: " + dic_path)
      return None
    }
  }
  let config = match @lib.parse_aff(aff_text) {
    Ok(value) => value
    Err(_) => {
      println("Failed to parse affix file: " + aff_path)
      return None
    }
  }
  let dictionary = match @lib.parse_dic(dic_text) {
    Ok(value) => value
    Err(_) => {
      println("Failed to parse dictionary file: " + dic_path)
      return None
    }
  }
  Some((config, dictionary))
}

///|
fn validate(args : Array[String]) -> Unit {
  if args.length() < 4 {
    usage()
    return
  }
  match load(args[2], args[3]) {
    Some((config, dictionary)) => {
      println("affix directives parsed: " + config.prefixes.length().to_string() + " prefixes, " + config.suffixes.length().to_string() + " suffixes")
      println("dictionary entries parsed: " + dictionary.entries.length().to_string())
    }
    None => ()
  }
}

///|
fn check(args : Array[String]) -> Unit {
  if args.length() < 5 {
    usage()
    return
  }
  match load(args[2], args[3]) {
    Some((config, dictionary)) => {
      for i in 4..<args.length() {
        let word = args[i]
        let result = @lib.spell(dictionary, config, word)
        if result.accepted {
          println(word + ": accepted")
        } else {
          println(word + ": rejected")
        }
      }
    }
    None => ()
  }
}

///|
fn suggest(args : Array[String]) -> Unit {
  if args.length() < 5 {
    usage()
    return
  }
  match load(args[2], args[3]) {
    Some((config, dictionary)) => {
      let word = args[4]
      let limit = parse_limit(args)
      let suggestions = @lib.suggest(dictionary, config, word, limit)
      if suggestions.length() == 0 {
        println("No suggestions")
      } else {
        for suggestion in suggestions {
          println(suggestion.word + " " + suggestion.distance.to_string())
        }
      }
    }
    None => ()
  }
}

///|
fn check_file(args : Array[String]) -> Unit {
  if args.length() < 5 {
    usage()
    return
  }
  match load(args[2], args[3]) {
    Some((config, dictionary)) => {
      let text = match read_file(args[4]) {
        Some(value) => value
        None => {
          println("Failed to read word file: " + args[4])
          return
        }
      }
      for line in text.split("\n") {
        let word = line.trim().to_owned()
        if !word.is_empty() {
          let status = if @lib.spell(dictionary, config, word).accepted {
            "accepted"
          } else {
            "rejected"
          }
          println(word + "\t" + status)
        }
      }
    }
    None => ()
  }
}

///|
fn suggest_file(args : Array[String]) -> Unit {
  if args.length() < 5 {
    usage()
    return
  }
  match load(args[2], args[3]) {
    Some((config, dictionary)) => {
      let text = match read_file(args[4]) {
        Some(value) => value
        None => {
          println("Failed to read word file: " + args[4])
          return
        }
      }
      let limit = parse_limit(args)
      for line in text.split("\n") {
        let word = line.trim().to_owned()
        if !word.is_empty() {
          let suggestions = @lib.suggest(dictionary, config, word, limit)
          let words : Array[String] = []
          for suggestion in suggestions {
            words.push(suggestion.word)
          }
          println(word + "\t" + words.join(", "))
        }
      }
    }
    None => ()
  }
}
///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  match args[1] {
    "validate" => validate(args)
    "check" => check(args)
    "suggest" => suggest(args)
    "check-file" => check_file(args)
    "suggest-file" => suggest_file(args)
    "version" | "--version" | "-v" => println("MoonSpell " + @lib.version())
    _ => usage()
  }
}
