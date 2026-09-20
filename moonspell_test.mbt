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

test "compound flag and minimum length" {
  let dictionary = @moonspell.parse_dic("4\nfoo/A\nbar/A\nxy/A\nyz/A\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDMIN 3\nCOMPOUNDFLAG A\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "foobar").accepted)
  assert_true(@moonspell.spell(dictionary, config, "barfoo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foobarfoo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "xyyz").accepted)
  assert_false(@moonspell.spell(dictionary, config, "fooxy").accepted)
  assert_false(@moonspell.spell(dictionary, config, "xyfoo").accepted)
}

test "compound affixes stay in permitted positions" {
  let dictionary = @moonspell.parse_dic("2\nfoo/XPS\nbar/XPS\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDFLAG X\nPFX P Y 1\nPFX P 0 pre .\nSFX S Y 1\nSFX S 0 suf .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "prefoo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foosuf").accepted)
  assert_true(@moonspell.spell(dictionary, config, "prefoobarsuf").accepted)
  assert_false(@moonspell.spell(dictionary, config, "foosufbar").accepted)
  assert_false(@moonspell.spell(dictionary, config, "fooprebarsuf").accepted)
}

test "ONLYINCOMPOUND words cannot stand alone" {
  let dictionary = @moonspell.parse_dic("2\nfoo/A\npseudo/OAB\n").unwrap()
  let config = @moonspell.parse_aff("ONLYINCOMPOUND O\nCOMPOUNDFLAG A\nSFX B Y 1\nSFX B 0 s .\n").unwrap()
  assert_false(@moonspell.spell(dictionary, config, "pseudo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "pseudos").accepted)
  assert_true(@moonspell.spell(dictionary, config, "pseudofoo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foopseudo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foopseudos").accepted)
}
test "CHECKCOMPOUNDDUP only rejects a duplicated final component" {
  let dictionary = @moonspell.parse_dic("2\nfoo/A\nbar/A\n").unwrap()
  let config = @moonspell.parse_aff("CHECKCOMPOUNDDUP\nCOMPOUNDFLAG A\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "foofoobar").accepted)
  assert_false(@moonspell.spell(dictionary, config, "foofoo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "foobarbar").accepted)
}

test "CHECKCOMPOUNDCASE rejects uppercase at compound boundaries" {
  let dictionary = @moonspell.parse_dic("4\nfoo/A\nBar/A\nBAZ/A\n-/A\n").unwrap()
  let config = @moonspell.parse_aff("CHECKCOMPOUNDCASE\nCOMPOUNDFLAG A\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "Barfoo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foo-Bar").accepted)
  assert_false(@moonspell.spell(dictionary, config, "fooBar").accepted)
  assert_false(@moonspell.spell(dictionary, config, "BAZBar").accepted)
}

test "CHECKCOMPOUNDTRIPLE rejects triple letters at boundaries" {
  let dictionary = @moonspell.parse_dic("4\nfoo/A\nopera/A\neel/A\nbare/A\n").unwrap()
  let config = @moonspell.parse_aff("CHECKCOMPOUNDTRIPLE\nCOMPOUNDFLAG A\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "operafoo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "fooopera").accepted)
  assert_false(@moonspell.spell(dictionary, config, "bareeel").accepted)
}

test "COMPOUNDPERMITFLAG allows affixes inside compounds" {
  let dictionary = @moonspell.parse_dic("2\nfoo/XPS\nbar/XPS\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDFLAG X\nCOMPOUNDPERMITFLAG Y\nPFX P Y 1\nPFX P 0 pre/Y .\nSFX S Y 1\nSFX S 0 suf/Y .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "foosufbar").accepted)
  assert_true(@moonspell.spell(dictionary, config, "fooprebarsuf").accepted)
  assert_true(@moonspell.spell(dictionary, config, "prefooprebarsuf").accepted)
}

test "COMPOUNDFORBIDFLAG removes affixed forms from compounds" {
  let dictionary = @moonspell.parse_dic("2\nfoo/XPS\nbar/XPS\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDFLAG X\nCOMPOUNDFORBIDFLAG Z\nPFX P Y 1\nPFX P 0 pre/Z .\nSFX S Y 1\nSFX S 0 suf/Z .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "prefoo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foosuf").accepted)
  assert_false(@moonspell.spell(dictionary, config, "prefoobarsuf").accepted)
  assert_false(@moonspell.spell(dictionary, config, "foosufbar").accepted)
}

test "KEEPCASE blocks case-folded variants" {
  let dictionary = @moonspell.parse_dic("3\ncafé/K\nfoo/K\nbar\n").unwrap()
  let config = @moonspell.parse_aff("KEEPCASE K\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "café").accepted)
  assert_false(@moonspell.spell(dictionary, config, "Café").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "Foo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "Bar").accepted)
}
test "REP suggestions take priority and support spaces" {
  let dictionary = @moonspell.parse_dic("2\na\nlot\n").unwrap()
  let config = @moonspell.parse_aff("REP 1\nREP alot a_lot\n").unwrap()
  let suggestions = @moonspell.suggest(dictionary, config, "alot", 3)
  assert_true(suggestions.length() > 0)
  assert_eq(suggestions[0].word, "a lot")
}

test "MAP suggestions restore mapped characters" {
  let dictionary = @moonspell.parse_dic("1\ncafé\n").unwrap()
  let config = @moonspell.parse_aff("MAP 1\nMAP eé\n").unwrap()
  let suggestions = @moonspell.suggest(dictionary, config, "cafe", 3)
  assert_true(suggestions.length() > 0)
  assert_eq(suggestions[0].word, "café")
}

test "TRY suggestions generate one-edit candidates" {
  let dictionary = @moonspell.parse_dic("1\nform\n").unwrap()
  let config = @moonspell.parse_aff("TRY r\n").unwrap()
  let suggestions = @moonspell.suggest(dictionary, config, "fom", 3)
  assert_true(suggestions.length() > 0)
  assert_eq(suggestions[0].word, "form")
}
test "COMPOUNDRULE matches exact flag sequences" {
  let dictionary = @moonspell.parse_dic("3\na/A\nb/B\nc/BC\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDMIN 1\nCOMPOUNDRULE 1\nCOMPOUNDRULE ABC\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "abc").accepted)
  assert_true(@moonspell.spell(dictionary, config, "acc").accepted)
  assert_false(@moonspell.spell(dictionary, config, "ba").accepted)
  assert_false(@moonspell.spell(dictionary, config, "aa").accepted)
}

test "COMPOUNDRULE supports star and optional quantifiers" {
  let dictionary = @moonspell.parse_dic("3\na/A\nb/B\nc/C\n").unwrap()
  let star = @moonspell.parse_aff("COMPOUNDMIN 1\nCOMPOUNDRULE 1\nCOMPOUNDRULE A*B*C*\n").unwrap()
  assert_true(@moonspell.spell(dictionary, star, "aa").accepted)
  assert_true(@moonspell.spell(dictionary, star, "aabbcc").accepted)
  assert_true(@moonspell.spell(dictionary, star, "cc").accepted)
  assert_false(@moonspell.spell(dictionary, star, "ba").accepted)
  let optional = @moonspell.parse_aff("COMPOUNDMIN 1\nCOMPOUNDRULE 1\nCOMPOUNDRULE A?B?C?\n").unwrap()
  assert_true(@moonspell.spell(dictionary, optional, "a").accepted)
  assert_true(@moonspell.spell(dictionary, optional, "abc").accepted)
  assert_true(@moonspell.spell(dictionary, optional, "bc").accepted)
  assert_false(@moonspell.spell(dictionary, optional, "aa").accepted)
  assert_false(@moonspell.spell(dictionary, optional, "abcc").accepted)
}
test "CHECKCOMPOUNDPATTERN forbids configured boundaries" {
  let dictionary = @moonspell.parse_dic("2\nfoo/A\nbar/A\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDFLAG A\nCHECKCOMPOUNDPATTERN 1\nCHECKCOMPOUNDPATTERN o b\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "barfoo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "foobar").accepted)
}

test "CHECKCOMPOUNDREP rejects compounds correctable to a dictionary word" {
  let dictionary = @moonspell.parse_dic("3\nfoo/A\nbar/A\nfxobar\n").unwrap()
  let config = @moonspell.parse_aff("CHECKCOMPOUNDREP\nCOMPOUNDFLAG A\nREP 1\nREP o x\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "barfoo").accepted)
  assert_false(@moonspell.spell(dictionary, config, "foobar").accepted)
}
test "forbidden homonyms block case-folded variants" {
  let dictionary = @moonspell.parse_dic("3\nkg\nKg/X\nKG/X\n").unwrap()
  let config = @moonspell.parse_aff("FORBIDDENWORD X\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "kg").accepted)
  assert_false(@moonspell.spell(dictionary, config, "Kg").accepted)
  assert_false(@moonspell.spell(dictionary, config, "KG").accepted)
}

test "NEEDAFFIX on affix continuation requires another affix" {
  let dictionary = @moonspell.parse_dic("1\nfoo/A\n").unwrap()
  let config = @moonspell.parse_aff("NEEDAFFIX X\nSFX A Y 1\nSFX A 0 s/XB .\nSFX B Y 1\nSFX B 0 baz .\n").unwrap()
  assert_false(@moonspell.spell(dictionary, config, "foos").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foosbaz").accepted)
}
test "dictionary word pairs block concatenated compounds" {
  let dictionary = @moonspell.parse_dic("3\nword/Y\ncompound/Y\ncompound word\n").unwrap()
  let config = @moonspell.parse_aff("COMPOUNDFLAG Y\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "word").accepted)
  assert_true(@moonspell.spell(dictionary, config, "compound").accepted)
  assert_false(@moonspell.spell(dictionary, config, "compoundword").accepted)
}
test "AF flag aliases expand dictionary and continuation flags" {
  let dictionary = @moonspell.parse_dic("1\nfoo/1\n").unwrap()
  let config = @moonspell.parse_aff("AF 2\nAF AB\nAF A\nSFX A Y 1\nSFX A 0 x .\nSFX B Y 1\nSFX B 0 y/2 .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "foo").accepted)
  assert_true(@moonspell.spell(dictionary, config, "foox").accepted)
  assert_true(@moonspell.spell(dictionary, config, "fooy").accepted)
  assert_true(@moonspell.spell(dictionary, config, "fooyx").accepted)
}
test "COMPLEXPREFIXES restores twofold prefixes in order" {
  let dictionary = @moonspell.parse_dic("1\nouro/B\n").unwrap()
  let config = @moonspell.parse_aff("COMPLEXPREFIXES\nPFX A Y 1\nPFX A 0 tek .\nPFX B Y 1\nPFX B 0 met/A .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "ouro").accepted)
  assert_true(@moonspell.spell(dictionary, config, "metouro").accepted)
  assert_true(@moonspell.spell(dictionary, config, "tekmetouro").accepted)
  assert_false(@moonspell.spell(dictionary, config, "tekouro").accepted)
  assert_false(@moonspell.spell(dictionary, config, "mettekouro").accepted)
}
test "CIRCUMFIX requires a matching prefix and suffix" {
  let dictionary = @moonspell.parse_dic("1\nnagy/C\n").unwrap()
  let config = @moonspell.parse_aff("CIRCUMFIX X\nPFX A Y 1\nPFX A 0 leg/X .\nPFX B Y 1\nPFX B 0 legesleg/X .\nSFX C Y 3\nSFX C 0 obb .\nSFX C 0 obb/AX .\nSFX C 0 obb/BX .\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "nagy").accepted)
  assert_true(@moonspell.spell(dictionary, config, "nagyobb").accepted)
  assert_true(@moonspell.spell(dictionary, config, "legnagyobb").accepted)
  assert_true(@moonspell.spell(dictionary, config, "legeslegnagyobb").accepted)
  assert_false(@moonspell.spell(dictionary, config, "legnagy").accepted)
  assert_false(@moonspell.spell(dictionary, config, "legeslegnagy").accepted)
}
test "ICONV normalizes input before lookup" {
  let dictionary = @moonspell.parse_dic("2\nChișinău\nț\n").unwrap()
  let config = @moonspell.parse_aff("ICONV 2\nICONV ş ș\nICONV ţ ț\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "Chişinău").accepted)
  assert_true(@moonspell.spell(dictionary, config, "ţ").accepted)
}
test "CHECKSHARPS handles ß and SS capitalization" {
  let dictionary = @moonspell.parse_dic("3\nmüßig/k\nAusstoß\nAußenabmessung\n").unwrap()
  let config = @moonspell.parse_aff("SET UTF-8\nCHECKSHARPS\nKEEPCASE k\n").unwrap()
  assert_true(@moonspell.spell(dictionary, config, "müßig").accepted)
  assert_true(@moonspell.spell(dictionary, config, "Müßig").accepted)
  assert_true(@moonspell.spell(dictionary, config, "MÜSSIG").accepted)
  assert_true(@moonspell.spell(dictionary, config, "AUSSTOSS").accepted)
  assert_true(@moonspell.spell(dictionary, config, "AUSSENABMESSUNG").accepted)
  assert_false(@moonspell.spell(dictionary, config, "MÜßIG").accepted)
}