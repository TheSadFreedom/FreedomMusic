import 'package:flutter_test/flutter_test.dart';
import 'package:freedom_music/data/track_key.dart';

void main() {
  test('trailing feat and prod credits are removed', () {
    expect(
      stripTrailingCredit('Song prod by xmindmemories'),
      'Song',
    );
    expect(
      stripTrailingCredit('Song (prod. by xmindmemories)'),
      'Song',
    );
    expect(stripTrailingCredit('Song feat. Shakewell'), 'Song');
    expect(stripTrailingCredit('Song (feat. Shakewell)'), 'Song');
    expect(
      stripTrailingCredit('Song feat. Shakewell (prod. by xmindmemories)'),
      'Song',
    );
    expect(stripTrailingCredit('Song [prod. by Name]'), 'Song');
    expect(stripTrailingCredit('Song - feat. Shakewell'), 'Song');
  });

  test('ordinary titles and years stay', () {
    expect(stripTrailingCredit('Bedlam'), 'Bedlam');
    expect(stripTrailingCredit('Bedlam (2026)'), 'Bedlam (2026)');
    expect(stripTrailingCredit('The Prod'), 'The Prod');
    expect(stripTrailingCredit('Hardcore'), 'Hardcore');
  });
}
