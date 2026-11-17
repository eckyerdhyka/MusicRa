import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'widgets/mini_player.dart';

/// Three tabs, each with its own navigator (so pages open "inside" a tab
/// like Spotify), plus the mini player docked above the tab bar.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _tab = 0;
  final _navKeys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  StreamSubscription<String>? _messages;

  static const _roots = [HomeScreen(), SearchScreen(), LibraryScreen()];

  @override
  void initState() {
    super.initState();
    _messages = ref.read(audioHandlerProvider).messages.listen((text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  void _select(int i) {
    if (i == _tab) {
      // Tapping the active tab again returns to its first page.
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = i);
    }
  }

  void _handleBack() {
    final nav = _navKeys[_tab].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else {
      // Leaves the app; playback continues in the background service.
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < 3; i++)
              HeroControllerScope.none(
                child: Navigator(
                  key: _navKeys[i],
                  onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _roots[i]),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x000A0D0B), Color(0xF00A0D0B), Colors.black],
              stops: [0, 0.35, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              _NavBar(index: _tab, onSelect: _select),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.search_rounded, Icons.manage_search_rounded, 'Cari'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Koleksi'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: InkResponse(
                  onTap: () => onSelect(i),
                  radius: 40,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        i == index ? _items[i].$2 : _items[i].$1,
                        color: i == index ? AppColors.text : AppColors.textMuted,
                        size: 26,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _items[i].$3,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                          color: i == index ? AppColors.text : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
