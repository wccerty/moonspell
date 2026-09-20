///|
/// Return the MoonSpell library version.
pub fn version() -> String {
  "0.1.0"
}

///|
/// Remove a leading UTF-8 byte-order mark from decoded text.
pub fn strip_bom(text : String) -> String {
  let chars = text.to_array()
  if chars.length() > 0 && chars[0].to_int() == 0xFEFF {
    text.view(start_offset=1).to_owned()
  } else {
    text
  }
}
