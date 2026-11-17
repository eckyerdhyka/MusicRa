import 'package:flutter_test/flutter_test.dart';
import 'package:musicra/youtube/models.dart';
import 'package:musicra/youtube/parsers.dart';

Map<String, dynamic> _run(String text, {String? browseId, String? pageType, String? videoId}) => {
      'text': text,
      if (browseId != null)
        'navigationEndpoint': {
          'browseEndpoint': {
            'browseId': browseId,
            if (pageType != null)
              'browseEndpointContextSupportedConfigs': {
                'browseEndpointContextMusicConfig': {'pageType': pageType},
              },
          },
        },
      if (videoId != null)
        'navigationEndpoint': {
          'watchEndpoint': {'videoId': videoId},
        },
    };

Map<String, dynamic> _flex(List<Map<String, dynamic>> runs) => {
      'musicResponsiveListItemFlexColumnRenderer': {
        'text': {'runs': runs},
      },
    };

/// Shape of a filtered song search row as returned with hl=id.
Map<String, dynamic> _songRow() => {
      'musicResponsiveListItemRenderer': {
        'thumbnail': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/a=w60-h60-l90-rj', 'width': 60},
                {'url': 'https://lh3.googleusercontent.com/a=w120-h120-l90-rj', 'width': 120},
              ],
            },
          },
        },
        'flexColumns': [
          _flex([_run('Hati-Hati di Jalan', videoId: 'E7kHvjvU6JY')]),
          _flex([
            _run('Tulus', browseId: 'UC_DHlXllTSMB8pTC38_leFg', pageType: 'MUSIC_PAGE_TYPE_ARTIST'),
            _run(' • '),
            _run('Manusia', browseId: 'MPREb_7FNmIeIV9kf', pageType: 'MUSIC_PAGE_TYPE_ALBUM'),
            _run(' • '),
            _run('4.02'),
          ]),
          _flex([_run('332 jt pemutaran')]),
        ],
        'playlistItemData': {'videoId': 'E7kHvjvU6JY'},
      },
    };

void main() {
  group('parseDuration', () {
    test('colon and Indonesian dot formats', () {
      expect(parseDuration('4:02'), 242);
      expect(parseDuration('4.02'), 242);
      expect(parseDuration('1:02:03'), 3723);
      expect(parseDuration('1.02.03'), 3723);
    });

    test('ignores non-durations', () {
      expect(parseDuration('332 jt pemutaran'), isNull);
      expect(parseDuration('2022'), isNull);
      expect(parseDuration('1.000'), isNull);
      expect(parseDuration(null), isNull);
    });
  });

  test('song search row → Song with artist, album, duration, art', () {
    final page = parseSearch({
      'contents': {
        'tabbedSearchResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicShelfRenderer': {
                          'contents': [_songRow()],
                          'continuations': [
                            {'nextContinuationData': {'continuation': 'NEXT'}},
                          ],
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    });
    expect(page.continuation, 'NEXT');
    expect(page.items, hasLength(1));
    final song = page.items.single.song!;
    expect(song.id, 'E7kHvjvU6JY');
    expect(song.title, 'Hati-Hati di Jalan');
    expect(song.artist, 'Tulus');
    expect(song.artistId, 'UC_DHlXllTSMB8pTC38_leFg');
    expect(song.album, 'Manusia');
    expect(song.albumId, 'MPREb_7FNmIeIV9kf');
    expect(song.durationSec, 242);
    expect(song.thumbnail, contains('w120-h120'));
  });

  test('album/playlist rows become browse items, type label stripped', () {
    final item = parseResponsiveItem({
      'flexColumns': [
        _flex([_run('Manusia')]),
        _flex([_run('Album'), _run(' • '), _run('Tulus'), _run(' • '), _run('2022')]),
      ],
      'navigationEndpoint': {
        'browseEndpoint': {
          'browseId': 'MPREb_7FNmIeIV9kf',
          'browseEndpointContextSupportedConfigs': {
            'browseEndpointContextMusicConfig': {'pageType': 'MUSIC_PAGE_TYPE_ALBUM'},
          },
        },
      },
    });
    expect(item!.type, YtItemType.album);
    expect(item.id, 'MPREb_7FNmIeIV9kf');
    expect(item.subtitle, 'Tulus • 2022');
  });

  test('home carousel with two-row items', () {
    final feed = parseHome({
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicCarouselShelfRenderer': {
                          'header': {
                            'musicCarouselShelfBasicHeaderRenderer': {
                              'title': {'runs': [_run('Rilis baru')]},
                            },
                          },
                          'contents': [
                            {
                              'musicTwoRowItemRenderer': {
                                'title': {'runs': [_run('Manusia')]},
                                'subtitle': {'runs': [_run('Album'), _run(' • '), _run('Tulus')]},
                                'navigationEndpoint': {
                                  'browseEndpoint': {'browseId': 'MPREb_7FNmIeIV9kf'},
                                },
                              },
                            },
                            {
                              'musicTwoRowItemRenderer': {
                                'title': {'runs': [_run('Teh Hijau')]},
                                'subtitle': {
                                  'runs': [_run('Tulus', browseId: 'UC_DHlXllTSMB8pTC38_leFg')],
                                },
                                'navigationEndpoint': {
                                  'watchEndpoint': {'videoId': 'RO75uUZiAw0'},
                                },
                              },
                            },
                          ],
                        },
                      },
                    ],
                    'continuations': [
                      {'nextContinuationData': {'continuation': 'HOME2'}},
                    ],
                  },
                },
              },
            },
          ],
        },
      },
    });
    expect(feed.continuation, 'HOME2');
    expect(feed.sections.single.title, 'Rilis baru');
    final items = feed.sections.single.items;
    expect(items.first.type, YtItemType.album);
    expect(items.last.type, YtItemType.song);
    expect(items.last.song!.artist, 'Tulus');
    expect(feed.sections.single.isSongShelf, isFalse);
  });

  test('playlist page: header author from facepile, tracks, item continuation', () {
    final res = parseCollection({
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicResponsiveHeaderRenderer': {
                          'title': {'runs': [_run('Lagu Indonesia')]},
                          'subtitle': {'runs': [_run('Playlist'), _run(' • '), _run('2026')]},
                          'facepile': {
                            'avatarStackViewModel': {
                              'text': {'content': 'Aluna Music'},
                            },
                          },
                        },
                      },
                    ],
                  },
                },
              },
            },
          ],
          'secondaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'musicPlaylistShelfRenderer': {
                    'contents': [
                      _songRow(),
                      {
                        'continuationItemRenderer': {
                          'continuationEndpoint': {
                            'continuationCommand': {'token': 'MORE'},
                          },
                        },
                      },
                    ],
                  },
                },
              ],
            },
          },
        },
      },
    }, 'VLPL1');
    expect(res.page.title, 'Lagu Indonesia');
    expect(res.page.author, 'Aluna Music');
    expect(res.page.songs.single.id, 'E7kHvjvU6JY');
    expect(res.continuation, 'MORE');
  });

  test('playlist continuation (appendContinuationItemsAction)', () {
    final res = parseCollectionContinuation({
      'onResponseReceivedActions': [
        {
          'appendContinuationItemsAction': {
            'continuationItems': [_songRow()],
          },
        },
      ],
    });
    expect(res.songs.single.title, 'Hati-Hati di Jalan');
    expect(res.continuation, isNull);
  });

  test('radio panel unwraps wrapper renderers without counterpart duplicates', () {
    Map<String, dynamic> video(String id, String title) => {
          'videoId': id,
          'title': {'runs': [_run(title)]},
          'longBylineText': {
            'runs': [_run('Tulus', browseId: 'UC_DHlXllTSMB8pTC38_leFg'), _run(' • '), _run('Manusia', browseId: 'MPREb_x')],
          },
          'lengthText': {'runs': [_run('3:51')]},
        };
    final res = parseNext({
      'contents': {
        'playlistPanelRenderer': {
          'title': 'The Hit List',
          'contents': [
            {'playlistPanelVideoRenderer': video('a', 'Satu')},
            {
              'playlistPanelVideoWrapperRenderer': {
                'primaryRenderer': {'playlistPanelVideoRenderer': video('b', 'Dua')},
                'counterpart': [
                  {
                    'counterpartRenderer': {'playlistPanelVideoRenderer': video('b-video', 'Dua (MV)')},
                  },
                ],
              },
            },
          ],
          'continuations': [
            {'nextRadioContinuationData': {'continuation': 'RADIO2'}},
          ],
        },
      },
    });
    expect(res.songs.map((s) => s.id), ['a', 'b']);
    expect(res.songs.first.durationSec, 231);
    expect(res.songs.first.album, 'Manusia');
    expect(res.title, 'The Hit List');
    expect(res.continuation, 'RADIO2');
  });

  test('hiResThumb upsizes CDN thumbnails', () {
    expect(hiResThumb('https://lh3.googleusercontent.com/a=w120-h120-l90-rj'),
        'https://lh3.googleusercontent.com/a=w544-h544-l90-rj');
    expect(hiResThumb('https://i.ytimg.com/vi/x/sddefault.jpg'), 'https://i.ytimg.com/vi/x/hqdefault.jpg');
    expect(hiResThumb(null), isNull);
  });
}
