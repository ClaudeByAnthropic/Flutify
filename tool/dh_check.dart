// 临时自检：AP connect() / authenticate() 分阶段计时与异常栈。
import 'package:flutify_app/services/protocol/access_point.dart';

Future<void> main() async {
  final sw = Stopwatch()..start();
  try {
    final ap = await SpotifyAccessPoint.connect(host: 'ap-gae2.spotify.com', port: 4070);
    print('connect ok ${sw.elapsedMilliseconds}ms');
    try {
      await ap.authenticate(ApCredentials.accessToken('bogus'));
    } catch (e, s) {
      print('auth -> $e (${sw.elapsedMilliseconds}ms)\n$s');
    }
    ap.close();
  } catch (e, s) {
    print('connect failed ${sw.elapsedMilliseconds}ms: $e\n$s');
  }
}
