import 'package:flutter/material.dart';

/// Centralized SnackBar utility for Privacy Notes.
/// Enforces:
/// 1. Always clears existing SnackBars first (never stacks/queues).
/// 2. Auto-dismisses after 5 seconds (even with actions).
/// 3. Provides clean optional action callback.
abstract final class AppSnackBar {
  static const Duration defaultDuration = Duration(seconds: 5);

  static void show(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = defaultDuration,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        persist: false,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}
