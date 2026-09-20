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