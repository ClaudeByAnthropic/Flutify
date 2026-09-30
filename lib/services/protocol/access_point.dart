import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/proto_codec.dart';
import 'ap_codec.dart';
import 'ap_crypto.dart' as ap_crypto;

/// AP 包类型（librespot `packet.rs`）。
class ApPacketType {
  static const int ping = 0x04;
  static const int requestKey = 0x0c;
  static const int aesKey = 0x0d;
  static const int aesKeyError = 0x0e;
  static const int pong = 0x49;
  static const int pongAck = 0x4a;
  static const int login = 0xab;
  static const int apWelcome = 0xac;
  static const int authFailure = 0xad;
}

/// AP 登录凭据（`authentication.proto` LoginCredentials）。
class ApCredentials {
  /// AUTHENTICATION_USER_PASS。
  static const int typeUserPass = 0;

  /// AUTHENTICATION_STORED_SPOTIFY_CREDENTIALS（可复用 blob 原样回传）。
  static const int typeStoredCredentials = 1;

  /// AUTHENTICATION_SPOTIFY_TOKEN（Login5/OAuth 的 access_token）。
  static const int typeSpotifyToken = 3;

  final String? username;
  final int authType;
  final Uint8List authData;

  const ApCredentials({this.username, required this.authType, required this.authData});

  factory ApCredentials.accessToken(String token) =>
      ApCredentials(authType: typeSpotifyToken, authData: Uint8List.fromList(token.codeUnits));

  factory ApCredentials.password(String username, String password) => ApCredentials(
        username: username,
        authType: typeUserPass,
        authData: Uint8List.fromList(password.codeUnits),
      );

  factory ApCredentials.storedBlob(String username, Uint8List blob) =>
      ApCredentials(username: username, authType: typeStoredCredentials, authData: blob);
}

/// APWelcome 中的登录结果。
class ApWelcome {
  final String canonicalUsername;
  final int reusableAuthType;
  final Uint8List reusableAuth;

  const ApWelcome({
    required this.canonicalUsername,
    required this.reusableAuthType,
    required this.reusableAuth,
  });
}

/// AP 登录失败（AuthFailure / APLoginFailed）。
class ApLoginException implements Exception {
  final int errorCode;
  final String? description;

  const ApLoginException(this.errorCode, [this.description]);

  static const _messages = <int, String>{
    0x00: '协议错误',
    0x02: '该接入点不可用，请换一个（TryAnotherAP）',
    0x05: '连接 ID 无效',
    0x09: '地区限制',
    0x0b: '需要 Premium 账号',
    0x0c: '凭据无效',
    0x0d: '凭据无法验证',
    0x0e: '账号已存在',
    0x0f: '需要额外验证',
    0x10: 'App Key 无效',
    0x11: '应用已被封禁',
  };

  String get message => (description != null && description!.isNotEmpty)
      ? description!
      : (_messages[errorCode] ?? 'AP 登录失败（错误码 $errorCode）');

  @override
  String toString() => message;
}

/// 取音频密钥失败。
class ApKeyException implements Exception {
  final int code;

  /// 服务端原始错误负载（供诊断）。
  final Uint8List raw;
  ApKeyException(this.code, [Uint8List? raw]) : raw = raw ?? Uint8List(0);

  @override
  String toString() => '获取音频密钥失败（错误码 $code${raw.isEmpty ? '' : ' raw=${raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'}）';
}

/// Spotify Access Point 会话：握手（DH + Shannon）→ 登录 → 取音频密钥。
///
/// 这是「完整曲目」链路里唯一必须走非 HTTP 协议的环节（音频密钥没有 REST 接口），
/// 其余（metadata / storage-resolve / CDN 下载）都是普通 HTTPS。对照 librespot
/// `connection/handshake.rs`、`session.rs`、`audio_key.rs` 与官方 `docs/connection.md`。
class SpotifyAccessPoint {
  final Socket _socket;

  /// 单订阅 socket 的常驻接收：握手期收明文帧，之后喂给 [ApCodec]。
  final BytesBuilder _preCodecBuffer = BytesBuilder();
  final List<Completer<({Uint8List payload, Uint8List raw})>> _handshakeFrames = [];
  ApCodec? _codec;

  final Map<int, Completer<Uint8List>> _pendingKeys = {};
  int _keySeq = 0;

  Completer<ApWelcome>? _loginWaiter;
  Timer? _pongTimer;
  bool _closed = false;

  /// 连接是否已关闭（服务端断开 / 出错 / 主动关闭），关闭后需重新 connect。
  bool get isClosed => _closed;

  /// 登录成功后的用户名（canonical）。
  String? canonicalUsername;

  /// 可复用凭据（APWelcome 返回，可持久化后免密重登）。
  ({int type, Uint8List blob})? reusableCredentials;

  SpotifyAccessPoint._(this._socket) {
    _socket.listen(
      (data) => _onBytes(Uint8List.fromList(data)),
      onError: _abort,
      onDone: () => _abort(StateError('AP 连接已关闭')),
      cancelOnError: true,
    );
  }

  // -------------------------------------------------------------------------
  // 连接与握手
  // -------------------------------------------------------------------------

  /// 解析接入点，返回单个随机候选（兼容旧调用）。
  static Future<({String host, int port})> resolveAccessPoint({http.Client? client}) async =>
      (await resolveAccessPoints(client: client)).first;

  /// 解析全部接入点（`https://apresolve.spotify.com/?type=accesspoint`）。
  ///
  /// 排序规则：端口 4070 → 443 → 80（部分代理 / TUN 环境会丢弃 :80 的非 HTTP 流量），
  /// 同端口内随机打散，分摊负载。
  static Future<List<({String host, int port})>> resolveAccessPoints({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(
            Uri.parse('https://apresolve.spotify.com/?type=accesspoint'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      final match = RegExp(r'"accesspoint"\s*:\s*\[([^\]]*)\]').firstMatch(res.body);
      final entries = RegExp(r'"([^"]+)"')
          .allMatches(match?.group(1) ?? '')
          .map((m) => m.group(1)!)
          .where((s) => s.contains(':'))
          .toList();
      if (entries.isEmpty) throw StateError('apresolve 未返回接入点');
      int rank(int port) => switch (port) { 4070 => 0, 443 => 1, _ => 2 };
      final parsed = [
        for (final e in entries) (host: e.split(':')[0], port: int.parse(e.split(':')[1])),
      ]..shuffle(Random.secure());
      parsed.sort((a, b) => rank(a.port).compareTo(rank(b.port)));
      return parsed;
    } finally {
      if (client == null) c.close();
    }
  }

  /// 连接接入点并完成握手（明文阶段：ClientHello → APResponse → ClientResponsePlaintext）。
  static Future<SpotifyAccessPoint> connect({
    String? host,
    int? port,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (host != null && port != null) {
      return _connectTo(host, port, timeout);
    }
    // 依次尝试候选：单个接入点不可达 / 被网络环境重置（部分地区只有个别接入点可达）
    // 不应让整条播放链路失败。上次连通的接入点排在最前，其后最多再试 [_maxAttempts] 个。
    final resolved = await resolveAccessPoints(client: client);
    final last = _lastGood;
    final candidates = <({String host, int port})>[
      ?last,
      ...resolved.where((c) => c != last),
    ];
    Object? lastError;
    for (final c in candidates.take(_maxAttempts)) {
      try {
        final ap = await _connectTo(c.host, c.port, timeout);
        _lastGood = c;
        return ap;
      } catch (e) {
        // 服务端明确拒绝（TryAnotherAP 除外），换接入点无意义
        if (e is ApLoginException && e.errorCode != 0x02) rethrow;
        if (c == _lastGood) _lastGood = null; // 曾经连通的接入点也可能失效
        lastError = e;
      }
    }
    throw lastError ?? StateError('没有可用的接入点');
  }

  /// 最近一次握手成功的接入点（进程内记忆，下次优先使用）。
  static ({String host, int port})? _lastGood;

  /// 单次 [connect] 最多尝试的接入点个数。
  static const int _maxAttempts = 6;

  /// 对单个接入点完成握手。
  static Future<SpotifyAccessPoint> _connectTo(String host, int port, Duration timeout) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    final ap = SpotifyAccessPoint._(socket);

    try {
      // 1) ClientHello：[0x00,0x04] + u32be(6+len) + payload
      final dh = ap_crypto.DhLocalKeys.random();
      final nonce = Uint8List(16);
      Random.secure().nextBytes(nonce);

      final buildInfo = ProtoWriter()
        ..varintAlways(10, 0) // product = PRODUCT_CLIENT
        ..varintAlways(20, 0) // product_flags = PRODUCT_FLAG_NONE
        ..varintAlways(30, 0x27) // platform = PLATFORM_WIN32_X86_64
        ..int64(40, 124200290); // version（对齐 Spotify 1.2.52.442）
      final dhHello = ProtoWriter()
        ..bytes(10, dh.publicKey)
        ..varintAlways(20, 1); // server_keys_known
      final loginCryptoHello = ProtoWriter()..message(10, dhHello);
      final hello = ProtoWriter()
        ..message(10, buildInfo)
        ..varintAlways(30, 0) // cryptosuites_supported = CRYPTO_SUITE_SHANNON
        ..message(50, loginCryptoHello)
        ..bytes(60, nonce)
        ..bytes(70, Uint8List.fromList([0x1e]));
      final helloBytes = hello.toBytes();
      final helloFrame = Uint8List.fromList([
        0x00, 0x04,
        ..._u32be(6 + helloBytes.length),
        ...helloBytes,
      ]);
      socket.add(helloFrame);

      // 2) APResponseMessage：u32be(整包长) + payload
      final respFrame = await ap._readHandshakeFrame(timeout);
      final resp = ProtoReader(respFrame.payload);

      Uint8List? gs;
      Uint8List? gsSignature;
      int? errorCode;
      resp.forEach((f) {
        if (f.number == 10 && f.wireType == 2) {
          // APChallenge
          f.asMessage.forEach((cf) {
            if (cf.number == 10 && cf.wireType == 2) {
              // LoginCryptoChallengeUnion
              cf.asMessage.forEach((df) {
                if (df.number == 10 && df.wireType == 2) {
                  df.asMessage.forEach((dd) {
                    if (dd.number == 10 && dd.wireType == 2) gs = dd.bytesValue;
                    if (dd.number == 30 && dd.wireType == 2) gsSignature = dd.bytesValue;
                  });
                }
              });
            }
          });
        }
        if (f.number == 30 && f.wireType == 2) {
          // APLoginFailed
          f.asMessage.forEach((lf) {
            if (lf.number == 10) errorCode = lf.varintValue;
          });
        }
      });
      if (errorCode != null) throw ApLoginException(errorCode!);
      final gsBytes = gs;
      final gsSigBytes = gsSignature;
      if (gsBytes == null || gsSigBytes == null) {
        throw StateError('APResponse 缺少 DH 挑战');
      }

      // 防中间人：验证服务端对 gs 的 RSA 签名
      if (!ap_crypto.rsaVerifyPkcs1Sha1(
        modulus: ap_crypto.apServerKey,
        signature: gsSigBytes,
        message: gsBytes,
      )) {
        throw StateError('AP 服务端签名验证失败');
      }

      // 3) 密钥推导（accumulated = ClientHello 帧 + APResponse 帧，均含帧头）
      final shared = dh.sharedSecret(gsBytes);
      final accumulated = Uint8List.fromList([...helloFrame, ...respFrame.raw]);
      final keys = ap_crypto.apComputeKeys(shared, accumulated);

      // 4) ClientResponsePlaintext：u32be(4+len) + payload
      final dhResp = ProtoWriter()..bytes(10, keys.challenge);
      final loginCryptoResp = ProtoWriter()..message(10, dhResp);
      final plain = ProtoWriter()
        ..message(10, loginCryptoResp)
        ..message(20, ProtoWriter()) // pow_response（空）
        ..message(30, ProtoWriter()); // crypto_response（空）
      final plainBytes = plain.toBytes();
      socket.add([..._u32be(4 + plainBytes.length), ...plainBytes]);
      await socket.flush();

      ap._installCodec(keys.sendKey, keys.recvKey);
      return ap;
    } catch (e) {
      ap.close();
      rethrow;
    }
  }

  /// 握手期读取一个明文帧：u32be(整包长) + payload（返回值含原始帧字节）。
  Future<({Uint8List payload, Uint8List raw})> _readHandshakeFrame(Duration timeout) {
    final completer = Completer<({Uint8List payload, Uint8List raw})>();
    _handshakeFrames.add(completer);
    return completer.future.timeout(timeout, onTimeout: () {
      _handshakeFrames.remove(completer);
      throw TimeoutException('等待 AP 握手响应超时');
    });
  }

  void _installCodec(Uint8List sendKey, Uint8List recvKey) {
    _codec = ApCodec(sendKey, recvKey);
    final leftover = _preCodecBuffer.takeBytes();
    if (leftover.isNotEmpty) _codec!.addIncoming(leftover);
    _drainCodec();
  }

  // -------------------------------------------------------------------------
  // 登录
  // -------------------------------------------------------------------------

  /// 在加密通道上登录（cmd 0xab），成功返回 [ApWelcome]。
  Future<ApWelcome> authenticate(ApCredentials credentials, {String? deviceId}) async {
    final os = switch (Platform.operatingSystem) {
      'windows' => 1, // OS_WINDOWS
      'macos' => 2, // OS_OSX
      'ios' => 3, // OS_IPHONE
      'linux' => 5, // OS_LINUX
      'android' => 7, // OS_ANDROID
      _ => 0,
    };
    final sysInfo = ProtoWriter()
      ..varintAlways(10, 2) // cpu_family = CPU_X86_64
      ..varintAlways(60, os)
      ..string(90, 'flutify-protocol')
      ..string(100, deviceId ?? '');
    final loginCreds = ProtoWriter()
      ..string(10, credentials.username ?? '')
      ..varintAlways(20, credentials.authType)
      ..bytes(30, credentials.authData);
    final packet = ProtoWriter()
      ..message(10, loginCreds)
      ..message(50, sysInfo)
      ..string(70, 'flutify 1.0');

    final waiter = Completer<ApWelcome>();
    _loginWaiter = waiter;
    _send(ApPacketType.login, packet.toBytes());

    try {
      final welcome = await waiter.future.timeout(const Duration(seconds: 15));
      canonicalUsername = welcome.canonicalUsername;
      reusableCredentials = (type: welcome.reusableAuthType, blob: welcome.reusableAuth);
      return welcome;
    } finally {
      if (identical(_loginWaiter, waiter)) _loginWaiter = null;
    }
  }

  // -------------------------------------------------------------------------
  // 音频密钥
  // -------------------------------------------------------------------------

  /// 请求曲目音频密钥（cmd 0x0c → 0x0d）。
  ///
  /// 请求 payload = `file_id(20) + gid(16) + seq(4 BE) + 0x0000(2)`；
  /// 响应 payload = `seq(4) + key(16)`。
  Future<Uint8List> requestAudioKey(Uint8List fileId, Uint8List trackGid) async {
    if (fileId.length != 20) throw ArgumentError('fileId must be 20 bytes');
    if (trackGid.length != 16) throw ArgumentError('gid must be 16 bytes');

    final seq = _keySeq++;
    final completer = Completer<Uint8List>();
    _pendingKeys[seq] = completer;

    final payload = Uint8List(20 + 16 + 4 + 2)
      ..setRange(0, 20, fileId)
      ..setRange(20, 36, trackGid)
      ..setRange(36, 40, _u32be(seq))
      ..setRange(40, 42, const [0, 0]);
    _send(ApPacketType.requestKey, payload);

    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      _pendingKeys.remove(seq);
    }
  }

  // -------------------------------------------------------------------------
  // 收发
  // -------------------------------------------------------------------------

  void _send(int cmd, Uint8List payload) {
    if (_closed) throw StateError('AP 会话已关闭');
    final codec = _codec;
    if (codec == null) throw StateError('AP 握手尚未完成');
    _socket.add(codec.encode(cmd, payload));
  }

  void _onBytes(Uint8List data) {
    final codec = _codec;
    if (codec == null) {
      // 握手阶段：明文帧 u32be(整包长) + payload
      _preCodecBuffer.add(data);
      final all = _preCodecBuffer.takeBytes();
      var offset = 0;
      while (all.length - offset >= 4) {
        final size = (all[offset] << 24) |
            (all[offset + 1] << 16) |
            (all[offset + 2] << 8) |
            all[offset + 3];
        if (all.length - offset < size) break;
        final raw = Uint8List.fromList(all.sublist(offset, offset + size));
        final payload = Uint8List.sublistView(raw, 4, size);
        offset += size;
        if (_handshakeFrames.isNotEmpty) {
          _handshakeFrames.removeAt(0).complete((payload: payload, raw: raw));
        }
      }
      if (offset < all.length) _preCodecBuffer.add(Uint8List.sublistView(all, offset));
      return;
    }

    codec.addIncoming(data);
    _drainCodec();
  }

  void _drainCodec() {
    final codec = _codec;
    if (codec == null) return;
    try {
      ApPacket? packet;
      while ((packet = codec.nextPacket()) != null) {
        _dispatch(packet!);
      }
    } catch (e, s) {
      _abort(e, s);
    }
  }

  void _dispatch(ApPacket packet) {
    switch (packet.cmd) {
      case ApPacketType.aesKey:
        final seq = _u32beAt(packet.payload, 0);
        final key = Uint8List.fromList(packet.payload.sublist(4, 20));
        _pendingKeys.remove(seq)?.complete(key);
        break;
      case ApPacketType.aesKeyError:
        final seq = _u32beAt(packet.payload, 0);
        final code = packet.payload.length > 4 ? packet.payload[4] : -1;
        _pendingKeys.remove(seq)?.completeError(ApKeyException(code, packet.payload));
        break;
      case ApPacketType.ping:
        // 对照 librespot：延迟 60s 回 4 字节零负载 Pong（服务端随后回 PongAck）
        _pongTimer?.cancel();
        _pongTimer = Timer(const Duration(seconds: 60), () {
          try {
            _send(ApPacketType.pong, Uint8List(4));
          } catch (_) {}
        });
        break;
      case ApPacketType.apWelcome:
        final reader = ProtoReader(packet.payload);
        var username = '';
        var reusableType = -1;
        var reusable = Uint8List(0);
        reader.forEach((f) {
          if (f.number == 10 && f.wireType == 2) username = f.asString;
          if (f.number == 30 && f.wireType == 0) reusableType = f.varintValue;
          if (f.number == 40 && f.wireType == 2) reusable = f.bytesValue;
        });
        final waiter = _loginWaiter;
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete(ApWelcome(
            canonicalUsername: username,
            reusableAuthType: reusableType,
            reusableAuth: reusable,
          ));
        }
        break;
      case ApPacketType.authFailure:
        final reader = ProtoReader(packet.payload);
        var code = -1;
        String? desc;
        reader.forEach((f) {
          if (f.number == 10 && f.wireType == 0) code = f.varintValue;
          if (f.number == 40 && f.wireType == 2) desc = f.asString;
        });
        final waiter = _loginWaiter;
        if (waiter != null && !waiter.isCompleted) {
          waiter.completeError(ApLoginException(code, desc));
        }
        break;
      default:
        // CountryCode / ProductInfo / PongAck 等：与取密钥无关，忽略
        break;
    }
  }

  void _abort(Object error, [StackTrace? st]) {
    if (_closed) return;
    _closed = true;
    _pongTimer?.cancel();
    for (final waiter in _pendingKeys.values) {
      if (!waiter.isCompleted) waiter.completeError(error, st);
    }
    _pendingKeys.clear();
    final login = _loginWaiter;
    if (login != null && !login.isCompleted) login.completeError(error, st);
    for (final frame in _handshakeFrames) {
      if (!frame.isCompleted) frame.completeError(error, st);
    }
    _handshakeFrames.clear();
    try {
      _socket.destroy();
    } catch (_) {}
  }

  /// 关闭会话。
  void close() {
    if (_closed) return;
    _closed = true;
    _pongTimer?.cancel();
    for (final waiter in _pendingKeys.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('AP 会话已关闭'));
    }
    _pendingKeys.clear();
    final login = _loginWaiter;
    if (login != null && !login.isCompleted) {
      login.completeError(StateError('AP 会话已关闭'));
    }
    for (final frame in _handshakeFrames) {
      if (!frame.isCompleted) frame.completeError(StateError('AP 会话已关闭'));
    }
    _handshakeFrames.clear();
    try {
      _socket.destroy();
    } catch (_) {}
  }

  static List<int> _u32be(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static int _u32beAt(Uint8List data, int offset) =>
      (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
}

extension on Random {
  void nextBytes(Uint8List out) {
    for (var i = 0; i < out.length; i++) {
      out[i] = nextInt(256);
    }
  }
}
