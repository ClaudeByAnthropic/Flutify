import 'zh_script_table.dart';

/// 简繁字形：判定一段中文偏简体还是繁体，并在两者之间逐字转换。
///
/// 映射表由 `tool/gen_zh_script_table.ps1` 从 Windows LCMapStringEx 导出（[zh_script_table.dart]），
/// 只做字级一对一替换，不处理词汇差异（如「软件 / 軟體」）——歌词对齐字形已经足够。
class ZhScript {
  ZhScript._();

  static final Map<int, int> _toSimp = _pairs(tradToSimpFrom, tradToSimpTo);
  static final Map<int, int> _toTrad = _pairs(simpToTradFrom, simpToTradTo);

  static Map<int, int> _pairs(String from, String to) {
    final a = from.codeUnits, b = to.codeUnits;
    return {for (var i = 0; i < a.length && i < b.length; i++) a[i]: b[i]};
  }

  /// 繁体专用字的个数（转简体后会变的字）。
  static int countTraditional(String text) => _count(text, _toSimp);

  /// 简体专用字的个数（转繁体后会变的字）。
  static int countSimplified(String text) => _count(text, _toTrad);

  static int _count(String text, Map<int, int> map) {
    var n = 0;
    for (final c in text.codeUnits) {
      if (map.containsKey(c)) n++;
    }
    return n;
  }

  /// 转为简体（[toSimplified] 为 true）或繁体；不认识的字原样保留。
  static String convert(String text, {required bool toSimplified}) {
    final map = toSimplified ? _toSimp : _toTrad;
    final units = text.codeUnits;
    List<int>? out;
    for (var i = 0; i < units.length; i++) {
      final mapped = map[units[i]];
      if (mapped == null) continue;
      (out ??= List.of(units))[i] = mapped;
    }
    return out == null ? text : String.fromCharCodes(out);
  }
}
