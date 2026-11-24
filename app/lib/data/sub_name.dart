/// A subscription's name made very short, to stand in a line with other things: the first word, in capitals, without
/// signs and what is in brackets ("ChillGuy VPN 🚀 (Недоступна)" gives "CHILLGUY"), at most eight letters.
String shortSub(String name) {
  var t = name.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
  t = t.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ').trim();
  if (t.isEmpty) return '';
  final first = t.split(RegExp(r'\s+')).first.toUpperCase();
  return first.length > 8 ? first.substring(0, 8) : first;
}
