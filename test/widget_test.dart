import 'package:flutter_test/flutter_test.dart';
import 'package:team_alarm1_2/main.dart'; // pubspec.yaml の name に合わせる

void main() {
  testWidgets('アプリ起動テスト', (WidgetTester tester) async {
    // RootApp をポンプ
    await tester.pumpWidget(const RootApp());

    // 最初の画面（グループ一覧）が表示されるか確認
    expect(find.text('グループ'), findsOneWidget);
  });
}
