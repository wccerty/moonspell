test "library version" {
  assert_eq(@moonspell.version(), "0.1.0")
}

test "parse dictionary entries and flags" {
  let dictionary = @moonspell.parse_dic("3\nhello\ncreated/U\ncan't/SM po:noun\n").unwrap()
  assert_eq(dictionary.declared_count, 3)
  assert_eq(dictionary.entries.length(), 3)
  assert_eq(dictionary.entries[0].word, "hello")
  assert_eq(dictionary.entries[1].word, "created")
  assert_eq(dictionary.entries[1].flags, "U")
  assert_eq(dictionary.entries[2].word, "can't")
  assert_eq(dictionary.entries[2].flags, "SM")
  assert_eq(dictionary.entries[2].morph, "po:noun")
  assert_true(dictionary.has_word("hello"))
  assert_false(dictionary.has_word("missing"))
}

test "reject invalid dictionary header" {
  match @moonspell.parse_dic("words\nhello\n") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

test "parse core affix directives" {
  let source = "SET UTF-8\nFLAG long\nTRY abc\nWORDCHARS '-\nPFX A Y 1\nPFX A 0 re .\nSFX S Y 1\nSFX S 0 s [^s]\nREP 1\nREP f ph\nMAP 1\nMAP aá\n"
  let config = @moonspell.parse_aff(source).unwrap()
  assert_eq(config.encoding, "UTF-8")
  assert_eq(config.flag_mode, "long")
  assert_eq(config.try_chars, "abc")
  assert_eq(config.word_chars, "'-")
  assert_eq(config.prefixes.length(), 1)
  assert_eq(config.prefixes[0].flag, "A")
  assert_eq(config.prefixes[0].add, "re")
  assert_true(config.prefixes[0].cross_product)
  assert_eq(config.suffixes.length(), 1)
  assert_eq(config.suffixes[0].flag, "S")
  assert_eq(config.suffixes[0].condition, "[^s]")
  assert_eq(config.replacements.length(), 1)
  assert_eq(config.replacements[0].from, "f")
  assert_eq(config.replacements[0].to, "ph")
  assert_eq(config.maps.length(), 1)
}

test "reject malformed affix rule" {
  match @moonspell.parse_aff("PFX A Y 1\nPFX A 0\n") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}
test "basic spelling engine handles exact, prefix, suffix and cross product" {
  let dictionary = @moonspell.parse_dic("3\ncreate/U\nrun/S\nclear/UA\n").unwrap()
  let config = @moonspell.parse_aff("PFX U Y 1\nPFX U 0 un .\nSFX S Y 1\nSFX S 0 s .\nSFX A Y 1\nSFX A 0 ed .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "create").accepted)
  assert_true(@moonspell.spell(dictionary, config, "uncreate").accepted)
  assert_true(@moonspell.spell(dictionary, config, "runs").accepted)
  assert_true(@moonspell.spell(dictionary, config, "uncleared").accepted)
  assert_false(@moonspell.spell(dictionary, config, "missing").accepted)
}

test "basic spelling engine honors NEEDAFFIX and FORBIDDENWORD" {
  let dictionary = @moonspell.parse_dic("2\nroot/XU\nbad/F\n").unwrap()
  let config = @moonspell.parse_aff("NEEDAFFIX X\nFORBIDDENWORD F\nPFX U Y 1\nPFX U 0 un .\n").unwrap()
  assert_false(@moonspell.spell(dictionary, config, "root").accepted)
  assert_true(@moonspell.spell(dictionary, config, "unroot").accepted)
  assert_false(@moonspell.spell(dictionary, config, "bad").accepted)
}
test "levenshtein distance is stable" {
  assert_eq(@moonspell.levenshtein_distance("example", "example"), 0)
  assert_eq(@moonspell.levenshtein_distance("exsample", "example"), 1)
  assert_eq(@moonspell.levenshtein_distance("kitten", "sitting"), 3)
}

test "suggestion engine ranks dictionary candidates" {
  let dictionary = @moonspell.parse_dic("1\nexample\n").unwrap()
  let config = @moonspell.parse_aff("").unwrap()
  let suggestions = @moonspell.suggest(dictionary, config, "exsample", 3)
  assert_true(suggestions.length() > 0)
  assert_eq(suggestions[0].word, "example")
  assert_eq(suggestions[0].distance, 1)
}

test "suggestion engine includes generated affix forms" {
  let dictionary = @moonspell.parse_dic("1\ncreate/U\n").unwrap()
  let config = @moonspell.parse_aff("PFX U Y 1\nPFX U 0 un .\n").unwrap()
  let suggestions = @moonspell.suggest(dictionary, config, "uncreat", 3)
  assert_true(suggestions.length() > 0)
  assert_eq(suggestions[0].word, "uncreate")
}
test "long flags are matched as two-character units" {
  let dictionary = @moonspell.parse_dic("1\nroot/ABCD\n").unwrap()
  let config = @moonspell.parse_aff("FLAG long\nPFX AB Y 1\nPFX AB 0 ab .\nPFX BC Y 1\nPFX BC 0 bc .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "abroot").accepted)
  assert_false(@moonspell.spell(dictionary, config, "bcroot").accepted)
}

test "numeric flags are matched as comma-separated units" {
  let dictionary = @moonspell.parse_dic("1\nroot/1,2\n").unwrap()
  let config = @moonspell.parse_aff("FLAG num\nPFX 1 Y 1\nPFX 1 0 pre .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "preroot").accepted)
}

test "multi-character suffix conditions match the stem ending" {
  let dictionary = @moonspell.parse_dic("2\nhappy/Y\nboy/Y\n").unwrap()
  let config = @moonspell.parse_aff("SFX Y Y 2\nSFX Y y ier [^aeiou]y\nSFX Y 0 er [aeiou]y\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "happier").accepted)
  assert_false(@moonspell.spell(dictionary, config, "boier").accepted)
}

test "continuation flags allow a second suffix" {
  let dictionary = @moonspell.parse_dic("1\nread/X\n").unwrap()
  let config = @moonspell.parse_aff("SFX X Y 1\nSFX X 0 able/Y .\nSFX Y Y 1\nSFX Y 0 s .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "readables").accepted)
  assert_false(@moonspell.spell(dictionary, config, "readablex").accepted)
}
test "parsers accept a UTF-8 BOM" {
  let dictionary = @moonspell.parse_dic("\u{FEFF}1\nhello\n").unwrap()
  assert_true(dictionary.has_word("hello"))
  let config = @moonspell.parse_aff("\u{FEFF}SET UTF-8\n").unwrap()
  assert_eq(config.encoding, "UTF-8")
}
test "capitalization and trailing periods follow Hunspell basics" {
  let dictionary = @moonspell.parse_dic("5\nhello\nNASA\netc\ntext\nHunspell\n").unwrap()
  let config = @moonspell.parse_aff("").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "Hello").accepted)
  assert_true(@moonspell.spell(dictionary, config, "HELLO").accepted)
  assert_true(@moonspell.spell(dictionary, config, "NASA.").accepted)
  assert_true(@moonspell.spell(dictionary, config, "etc.").accepted)
  assert_true(@moonspell.spell(dictionary, config, "Text.").accepted)
  assert_true(@moonspell.spell(dictionary, config, "TEXT.").accepted)
  assert_true(@moonspell.spell(dictionary, config, "HUNSPELL.").accepted)
  assert_false(@moonspell.spell(dictionary, config, "Nasa").accepted)
}
