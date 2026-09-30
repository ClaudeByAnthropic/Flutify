import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutify_app/main.dart';
import 'package:flutify_app/services/audio_player_service.dart';
import 'package:flutify_app/services/spotify_api_service.dart';
import 'package:flutify_app/services/storage_service.dart';

void main() {
  testWidgets('FlutifyApp smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();
    final audio = AudioPlayerService();
    final api = SpotifyApiService(storage);

    await tester.pumpWidget(
      FlutifyApp(
        storageService: storage,
        audioPlayerService: audio,
        spotifyApiService: api,
      ),
    );

    // Initial pump
    await tester.pump(const Duration(milliseconds: 100));

    // Verify navigation bar or destinations exist
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('音乐库'), findsOneWidget);
  });
}
