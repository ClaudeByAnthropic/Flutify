import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_constants.dart';
import 'hashcash.dart';
import 'proto_codec.dart';

/// Login5 v3 认证（`login5.spotify.com/v3/login`）。
///
/// 支持：
/// - 密码登录（Password 凭据），自动求解 Hashcash 挑战；
/// - 短信验证码挑战（CodeChallenge）：返回 [Login5CodeRequired]，由上层收集验证码后
///   调用 [continueWithCode] 续接同一会话；
/// - 免密续期（StoredCredential 凭据）。
///
/// 每次请求都需带 client-token 头。
///
/// 挑战轮次规则：服务端每轮返回一组 challenges 与新的 login_context；
/// 下一轮请求必须携带新 login_context，并按 challenges 顺序逐一给出 solution（旧轮次的解作废）。
class Login5Service {
  final http.Client _client;

  /// 单次登录最多往返次数（hashcash → code → ok 一般 3 轮以内）。
  static const int _maxRounds = 6;

  Login5Service(this._client);

  /// 密码登录。
  Future<Login5Result> loginWithPassword({
    required String clientToken,
    required String deviceId,
    required String username,
    required String password,
  }) {
    // Password{ id=1, password=2 }
    final cred = ProtoWriter()
      ..string(1, username)
      ..string(2, password);
    final session = Login5Session._(
      clientToken: clientToken,
      deviceId: deviceId,
      loginMethodField: _LoginMethod.password,
      loginMethodMessage: cred.toBytes(),
    );
    return _run(session);
  }

  /// 用已保存的凭据免密续期，换取新的 access_token。
  Future<Login5Result> loginWithStoredCredential({
    required String clientToken,
    required String deviceId,
    required String username,
    required Uint8List data,
  }) {
    // StoredCredential{ username=1, data=2 }
    final cred = ProtoWriter()
      ..string(1, username)
      ..bytes(2, data);
    final session = Login5Session._(
      clientToken: clientToken,
      deviceId: deviceId,
      loginMethodField: _LoginMethod.storedCredential,
      loginMethodMessage: cred.toBytes(),
    );
    return _run(session);
  }

  /// 手机号登录：服务端下发短信验证码（返回 [Login5CodeRequired]），再用 [continueWithCode] 续接。
  ///
  /// [number] 为不含国家码的本地号码，[isoCountryCode] 如 `CN`，[callingCode] 如 `86`。
  Future<Login5Result> loginWithPhoneNumber({
    required String clientToken,
    required String deviceId,
    required String number,
    required String isoCountryCode,
    required String callingCode,
  }) {
    // PhoneNumber{ number=1, iso_country_code=2, country_calling_code=3 }
    final cred = ProtoWriter()
      ..string(1, number)
      ..string(2, isoCountryCode)
      ..string(3, callingCode);
    final session = Login5Session._(
      clientToken: clientToken,
      deviceId: deviceId,
      loginMethodField: _LoginMethod.phoneNumber,
      loginMethodMessage: cred.toBytes(),
    );
    return _run(session);
  }

  /// 一次性令牌登录（登录链接 / 设备联动下发的 token）。
  Future<Login5Result> loginWithOneTimeToken({
    required String clientToken,
    required String deviceId,
    required String token,
  }) {
    // OneTimeToken{ token=1 }
    final cred = ProtoWriter()..string(1, token);
    final session = Login5Session._(
      clientToken: clientToken,
      deviceId: deviceId,
      loginMethodField: _LoginMethod.oneTimeToken,
      loginMethodMessage: cred.toBytes(),
    );
    return _run(session);
  }

  /// 用同一凭据重新发起登录（重新发送短信验证码）。
  Future<Login5Result> restart(Login5Session session) {
    final fresh = Login5Session._(
      clientToken: session.clientToken,
      deviceId: session.deviceId,
      loginMethodField: session.loginMethodField,
      loginMethodMessage: session.loginMethodMessage,
    );
    return _run(fresh);
  }

  /// 收到短信验证码后续接登录。
  Future<Login5Result> continueWithCode(Login5Session session, String code) {
    final slot = session._pendingCodeSlot;
    if (slot == null) throw StateError('该会话没有待提交的验证码');
    // ChallengeSolution{ code=2 CodeSolution{ code=1 } }
    final codeSolution = ProtoWriter()..string(1, code.trim());
    final solution = ProtoWriter()..message(2, codeSolution);
    session._solutions[slot] = solution.toBytes();
    session._pendingCodeSlot = null;
    return _run(session);
  }

  /// 发送当前会话请求并处理挑战循环。
  Future<Login5Result> _run(Login5Session session) async {
    for (var round = 0; round < _maxRounds; round++) {
      _log('→ 第 ${round + 1} 轮 method=${session.loginMethodField} '
          'context=${session._loginContext.length}B solutions=${session._solutions.whereType<Uint8List>().length}');
      final response = await _post(session._buildRequest(), session.clientToken);
      final parsed = _parseResponse(response);
      _log('← ${parsed.describe()}');

      if (parsed.ok != null) return Login5Success(parsed.ok!);

      if (parsed.error != null) {
        // 仅"超时"原样重试；尝试过多 / 稍后再试属于风控，重试只会更糟
        if (parsed.error == Login5Error.timeout) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        throw Login5Failure(parsed.error!);
      }

      if (parsed.challenges.isEmpty) {
        throw StateError('Login5 返回了无法处理的响应（无令牌、无错误、无挑战）');
      }

      // 进入新一轮：换上最新 login_context，旧解全部作废
      session._loginContext = parsed.loginContext;
      session._solutions = List<Uint8List?>.filled(parsed.challenges.length, null);

      _CodeChallenge? codeChallenge;
      for (var i = 0; i < parsed.challenges.length; i++) {
        final c = parsed.challenges[i];
        if (c is _HashcashChallenge) {
          session._solutions[i] = await _solveHashcash(parsed.loginContext, c);
        } else if (c is _CodeChallenge) {
          codeChallenge = c;
          session._pendingCodeSlot = i;
        } else {
          // 如 reCAPTCHA 等需网页交互的挑战，原生协议层无法完成
          throw const Login5UnsupportedChallenge();
        }
      }

      if (codeChallenge != null) {
        // 短信已下发：交给上层收集验证码，再用 continueWithCode 续接
        return Login5CodeRequired(
          session: session,
          codeLength: codeChallenge.codeLength,
          canonicalPhoneNumber: codeChallenge.canonicalPhoneNumber,
        );
      }
    }
    throw StateError('Login5 挑战轮次过多，已中止');
  }

  Future<Uint8List> _post(Uint8List body, String clientToken) async {
    final res = await _client.post(
      Uri.parse(SpotifyAuthConstants.login5Endpoint),
      headers: {
        'Accept': 'application/x-protobuf',
        'Content-Type': 'application/x-protobuf',
        'User-Agent': SpotifyAuthConstants.userAgent,
        'client-token': clientToken,
      },
      body: body,
    );
    if (res.statusCode != 200) {
      _log('← HTTP ${res.statusCode} ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
      throw StateError('Login5 HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  /// 调试日志：只记录轮次、字段号、错误码与挑战类型，不含密码、令牌等敏感内容。
  ///（纯 Dart 实现，保持本库可在无 Flutter 环境下运行，如 tool/protocol_probe.dart）
  static void _log(String message) {
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      print('[Login5] $message');
    }
  }

  /// 求解 hashcash 并编码为
  /// ChallengeSolution{ hashcash=1 HashcashSolution{ suffix=1, duration=2 Duration{seconds=1,nanos=2} } }
  Future<Uint8List> _solveHashcash(Uint8List loginContext, _HashcashChallenge c) async {
    final watch = Stopwatch()..start();
    final suffix = await Hashcash.solveAsync(loginContext, c.prefix, c.length);
    watch.stop();

    final micros = watch.elapsedMicroseconds;
    final duration = ProtoWriter()
      ..int64(1, micros ~/ 1000000)
      ..int32(2, (micros % 1000000) * 1000);
    final hashcash = ProtoWriter()
      ..bytes(1, suffix)
      ..message(2, duration);
    final solution = ProtoWriter()..message(1, hashcash);
    return solution.toBytes();
  }

  // --- 响应解析 ---

  /// LoginResponse{ ok=1, error=2, challenges=3, login_context=5 }
  _LoginParsed _parseResponse(Uint8List data) {
    LoginOk? ok;
    Login5Error? error;
    var challenges = <_Challenge>[];
    Uint8List loginContext = Uint8List(0);

    ProtoReader(data).forEach((f) {
      switch (f.number) {
        case 1:
          ok = _parseLoginOk(f.asMessage);
          break;
        case 2: // LoginError 枚举，varint
          error = Login5Error.fromCode(f.varintValue);
          break;
        case 3:
          challenges = _parseChallenges(f.asMessage);
          break;
        case 5:
          loginContext = f.bytesValue;
          break;
      }
    });

    return _LoginParsed(ok: ok, error: error, challenges: challenges, loginContext: loginContext);
  }

  /// LoginOk{ username=1, access_token=2, stored_credential=3, access_token_expires_in=4 }
  LoginOk _parseLoginOk(ProtoReader r) {
    var username = '';
    var accessToken = '';
    Uint8List stored = Uint8List(0);
    var expiresIn = 3600;
    r.forEach((f) {
      switch (f.number) {
        case 1:
          username = f.asString;
          break;
        case 2:
          accessToken = f.asString;
          break;
        case 3:
          stored = Uint8List.fromList(f.bytesValue);
          break;
        case 4:
          expiresIn = f.varintValue;
          break;
      }
    });
    return LoginOk(
      username: username,
      accessToken: accessToken,
      storedCredential: stored,
      accessTokenExpiresIn: expiresIn,
    );
  }

  /// Challenges{ challenges=1 repeated Challenge{ hashcash=1, code=2 } }，保持原始顺序。
  List<_Challenge> _parseChallenges(ProtoReader r) {
    final list = <_Challenge>[];
    r.forEach((f) {
      if (f.number != 1) return;
      _Challenge challenge = const _UnknownChallenge();
      f.asMessage.forEach((c) {
        if (c.number == 1) {
          challenge = _parseHashcashChallenge(c.asMessage);
        } else if (c.number == 2) {
          challenge = _parseCodeChallenge(c.asMessage);
        }
      });
      list.add(challenge);
    });
    return list;
  }

  /// HashcashChallenge{ prefix=1 bytes, length=2 }
  _HashcashChallenge _parseHashcashChallenge(ProtoReader r) {
    Uint8List prefix = Uint8List(0);
    var length = 0;
    r.forEach((f) {
      if (f.number == 1) {
        prefix = Uint8List.fromList(f.bytesValue);
      } else if (f.number == 2) {
        length = f.varintValue;
      }
    });
    return _HashcashChallenge(prefix: prefix, length: length);
  }

  /// CodeChallenge{ method=1, code_length=2, expires_in=3, canonical_phone_number=4 }
  _CodeChallenge _parseCodeChallenge(ProtoReader r) {
    var codeLength = 6;
    var phone = '';
    r.forEach((f) {
      if (f.number == 2) {
        codeLength = f.varintValue;
      } else if (f.number == 4) {
        phone = f.asString;
      }
    });
    return _CodeChallenge(codeLength: codeLength, canonicalPhoneNumber: phone);
  }
}

/// LoginRequest 中 login_method oneof 的字段号。
class _LoginMethod {
  static const int storedCredential = 100;
  static const int password = 101;
  static const int phoneNumber = 103;
  static const int oneTimeToken = 104;
}

/// 一次登录会话的可变状态（跨挑战轮次保留）。
class Login5Session {
  final String clientToken;
  final String deviceId;
  final int loginMethodField;
  final Uint8List loginMethodMessage;

  Uint8List _loginContext = Uint8List(0);

  /// 与当前轮 challenges 一一对应的解；null 表示尚未求解。
  List<Uint8List?> _solutions = const [];

  /// 等待用户输入的验证码在 [_solutions] 中的位置。
  int? _pendingCodeSlot;

  Login5Session._({
    required this.clientToken,
    required this.deviceId,
    required this.loginMethodField,
    required this.loginMethodMessage,
  });

  /// 构造 LoginRequest{ client_info=1, login_context=2, challenge_solutions=3, `login_method`=100.. }
  Uint8List _buildRequest() {
    // ClientInfo{ client_id=1, device_id=2 }
    final clientInfo = ProtoWriter()
      ..string(1, SpotifyAuthConstants.clientId)
      ..string(2, deviceId);

    final request = ProtoWriter()..message(1, clientInfo);

    if (_loginContext.isNotEmpty) {
      request.bytes(2, _loginContext);
    }

    final ready = _solutions.whereType<Uint8List>().toList();
    if (ready.isNotEmpty) {
      // ChallengeSolutions{ solutions=1 repeated ChallengeSolution }
      final solutions = ProtoWriter();
      for (final s in ready) {
        solutions.bytes(1, s);
      }
      request.message(3, solutions);
    }

    request.bytes(loginMethodField, loginMethodMessage);
    return request.toBytes();
  }
}

/// 登录结果：成功，或需要用户输入短信验证码。
sealed class Login5Result {
  const Login5Result();
}

class Login5Success extends Login5Result {
  final LoginOk ok;
  const Login5Success(this.ok);
}

class Login5CodeRequired extends Login5Result {
  /// 续接用的会话，传回 [Login5Service.continueWithCode]。
  final Login5Session session;

  /// 验证码长度（CodeChallenge.code_length）。
  final int codeLength;

  /// 目标手机号（服务端脱敏）。
  final String canonicalPhoneNumber;

  const Login5CodeRequired({
    required this.session,
    required this.codeLength,
    required this.canonicalPhoneNumber,
  });
}

/// LoginOk 数据。
class LoginOk {
  final String username;
  final String accessToken;
  final Uint8List storedCredential;
  final int accessTokenExpiresIn;

  LoginOk({
    required this.username,
    required this.accessToken,
    required this.storedCredential,
    required this.accessTokenExpiresIn,
  });
}

class _LoginParsed {
  final LoginOk? ok;
  final Login5Error? error;
  final List<_Challenge> challenges;
  final Uint8List loginContext;
  _LoginParsed({this.ok, this.error, required this.challenges, required this.loginContext});

  String describe() {
    if (ok != null) return 'ok（expires_in=${ok!.accessTokenExpiresIn}s, stored_credential=${ok!.storedCredential.length}B）';
    if (error != null) return 'error code=${error!.code}（${error!.name}）';
    final types = challenges.map((c) => switch (c) {
          _HashcashChallenge(:final length) => 'hashcash(len=$length)',
          _CodeChallenge() => 'code',
          _UnknownChallenge() => 'unknown',
        });
    return 'challenges=[${types.join(', ')}] context=${loginContext.length}B';
  }
}

sealed class _Challenge {
  const _Challenge();
}

class _HashcashChallenge extends _Challenge {
  final Uint8List prefix;
  final int length;
  const _HashcashChallenge({required this.prefix, required this.length});
}

class _CodeChallenge extends _Challenge {
  final int codeLength;
  final String canonicalPhoneNumber;
  const _CodeChallenge({required this.codeLength, required this.canonicalPhoneNumber});
}

class _UnknownChallenge extends _Challenge {
  const _UnknownChallenge();
}
