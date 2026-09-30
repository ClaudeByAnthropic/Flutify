/// 手机号登录可选的国家 / 地区（Login5 PhoneNumber 需要 ISO 代码与国际区号）。
class PhoneRegion {
  final String isoCode;
  final String callingCode;
  final String name;
  final String flag;

  const PhoneRegion(this.isoCode, this.callingCode, this.name, this.flag);

  String get label => '$flag  +$callingCode';
}

class PhoneRegions {
  PhoneRegions._();

  static const PhoneRegion defaultRegion = PhoneRegion('CN', '86', '中国大陆', '🇨🇳');

  static const List<PhoneRegion> all = [
    defaultRegion,
    PhoneRegion('HK', '852', '中国香港', '🇭🇰'),
    PhoneRegion('MO', '853', '中国澳门', '🇲🇴'),
    PhoneRegion('TW', '886', '中国台湾', '🇹🇼'),
    PhoneRegion('US', '1', '美国', '🇺🇸'),
    PhoneRegion('CA', '1', '加拿大', '🇨🇦'),
    PhoneRegion('GB', '44', '英国', '🇬🇧'),
    PhoneRegion('JP', '81', '日本', '🇯🇵'),
    PhoneRegion('KR', '82', '韩国', '🇰🇷'),
    PhoneRegion('SG', '65', '新加坡', '🇸🇬'),
    PhoneRegion('MY', '60', '马来西亚', '🇲🇾'),
    PhoneRegion('AU', '61', '澳大利亚', '🇦🇺'),
    PhoneRegion('DE', '49', '德国', '🇩🇪'),
    PhoneRegion('FR', '33', '法国', '🇫🇷'),
    PhoneRegion('IN', '91', '印度', '🇮🇳'),
    PhoneRegion('BR', '55', '巴西', '🇧🇷'),
  ];
}
