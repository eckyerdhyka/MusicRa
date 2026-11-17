import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../youtube/innertube.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.padding = const EdgeInsets.all(48)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2.6)),
      );
}

/// Friendly text for a failed network call.
String describeError(Object error) {
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
    return 'Tidak ada koneksi internet.';
  }
  if (s.contains('TimeoutException')) return 'Koneksi lambat, coba lagi.';
  if (error is InnerTubeException && error.statusCode == 429) {
    return 'YouTube sedang membatasi permintaan. Tunggu sebentar.';
  }
  return 'Terjadi kesalahan saat memuat data.';
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });

  final Object error;
  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 52, color: AppColors.textFaint),
          const SizedBox(height: 16),
          Text(describeError(error), style: t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
          if (onSecondary != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel ?? '')),
          ],
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: AppColors.textFaint),
          const SizedBox(height: 14),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: t.bodyMedium?.copyWith(color: AppColors.textMuted), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
}
