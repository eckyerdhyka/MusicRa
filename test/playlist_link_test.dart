import 'package:flutter_test/flutter_test.dart';
import 'package:musicra/youtube/playlist_link.dart';

void main() {
  group('parsePlaylistId', () {
    test('YouTube Music playlist link', () {
      expect(parsePlaylistId('https://music.youtube.com/playlist?list=PLkbaG37V-vG8Fib_qvgOKf3qzqA0SUk59'),
          'PLkbaG37V-vG8Fib_qvgOKf3qzqA0SUk59');
    });

    test('youtube.com link with share tracking params', () {
      expect(parsePlaylistId('https://youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI&si=AbCdEf123'),
          'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
    });

    test('watch link that carries a playlist', () {
      expect(parsePlaylistId('https://www.youtube.com/watch?v=E7kHvjvU6JY&list=RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs'),
          'RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs');
    });

    test('share text with words around the link', () {
      expect(
        parsePlaylistId('Dengerin ini deh: https://music.youtube.com/playlist?list=OLAK5uy_kXyz1234567890abc mantap'),
        'OLAK5uy_kXyz1234567890abc',
      );
    });

    test('browse URL with VL prefix', () {
      expect(parsePlaylistId('https://music.youtube.com/browse/VLPLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'),
          'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
    });

    test('link without scheme', () {
      expect(parsePlaylistId('youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'),
          'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
    });

    test('bare playlist id', () {
      expect(parsePlaylistId('PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'), 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
      expect(parsePlaylistId('VLPLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'), 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI');
    });

    test('rejects non-playlist input', () {
      expect(parsePlaylistId('https://www.youtube.com/watch?v=E7kHvjvU6JY'), isNull);
      expect(parsePlaylistId('https://youtu.be/E7kHvjvU6JY'), isNull);
      expect(parsePlaylistId('tulus hati-hati di jalan'), isNull);
      expect(parsePlaylistId('https://example.com/?list=PL123'), isNull);
      expect(parsePlaylistId(''), isNull);
    });
  });

  test('parseAlbumBrowseId', () {
    expect(parseAlbumBrowseId('https://music.youtube.com/browse/MPREb_7FNmIeIV9kf'), 'MPREb_7FNmIeIV9kf');
    expect(parseAlbumBrowseId('https://music.youtube.com/playlist?list=PL1'), isNull);
  });

  test('isRadioPlaylist', () {
    expect(isRadioPlaylist('RDAMVME7kHvjvU6JY'), isTrue);
    expect(isRadioPlaylist('RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs'), isFalse);
    expect(isRadioPlaylist('PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI'), isFalse);
  });
}
