import 'package:flutter_test/flutter_test.dart';
import 'package:freedom_music/models/track.dart';

void main() {
  test('Battle-Rap matches hyphen, space, and a mixed genre list', () {
    expect(isBattleGenre('Battle-Rap'), isTrue);
    expect(isBattleGenre('battle rap'), isTrue);
    expect(isBattleGenre('Hip-Hop / Battle_Rap'), isTrue);
    expect(isBattleGenre('Hip-Hop, Rap'), isFalse);
    expect(isBattleGenre(''), isFalse);
  });
}
