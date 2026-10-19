import 'package:flutter_test/flutter_test.dart';
import 'package:freedom_music/models/playlist_mosaic.dart';

void main() {
  test('one image stays a single cover', () {
    final covers = pickPlaylistMosaic(
      ['a', 'a', 'a'],
      seed: 1,
    );
    expect(covers, ['a']);
  });

  test('identical images in different files stay one cover', () {
    final covers = pickPlaylistMosaic(
      ['a.jpg', 'b.jpg', 'c.jpg'],
      seed: 3,
      identity: (path) => 'same',
    );
    expect(covers, hasLength(1));
  });

  test('two or three different covers fill four cells', () {
    final two = pickPlaylistMosaic(
      ['a', 'b'],
      seed: 1,
      identity: (path) => path,
    );
    expect(two.toSet(), {'a', 'b'});
    expect(two, hasLength(4));

    final three = pickPlaylistMosaic(
      ['a', 'b', 'c'],
      seed: 2,
      identity: (path) => path,
    );
    expect(three.toSet(), {'a', 'b', 'c'});
    expect(three, hasLength(4));
  });

  test('four or more different covers stay four unique cells', () {
    final covers = pickPlaylistMosaic(
      ['a', 'b', 'c', 'd', 'e'],
      seed: 4,
      identity: (path) => path,
    );
    expect(covers.toSet(), hasLength(4));
    expect(covers, hasLength(4));
  });
}
