import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freedom_music/theme/app_theme.dart';
import 'package:freedom_music/widgets/lyrics_view.dart';

void main() {
  testWidgets('lyrics stage shows the text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: SizedBox(
          width: 800,
          height: 600,
          child: LyricsStage(
            title: 'Прогулка',
            note: 'из фильма «Майор Гром»',
            raw: 'Первая строка\nВторая строка',
            fetching: false,
            notFound: false,
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('Первая строка'), findsOneWidget);
    expect(find.text('Вторая строка'), findsOneWidget);
  });
}
