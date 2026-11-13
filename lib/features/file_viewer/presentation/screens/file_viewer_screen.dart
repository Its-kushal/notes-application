import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_recovery_screen.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import 'package:leaflock/l10n/l10n_extension.dart';
import '../../../notes/domain/note.dart';
import '../../../notes/presentation/controllers/notes_providers.dart';
import '../../domain/file_decoder.dart';
import '../../domain/opened_file.dart';

class FileViewerScreen extends ConsumerStatefulWidget {
  final OpenedFile file;

  const FileViewerScreen({
    super.key,
    required this.file,
  });

  @override
  ConsumerState<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends ConsumerState<FileViewerScreen> {
  bool _isMonospace = false;
  bool _isSaving = false;
  late final List<String> _lines;

  @override
  void initState() {
    super.initState();
    _lines = _chunkText(widget.file.text);
  }

  static List<String> _chunkText(String text, {int maxChunkChars = 1000}) {
    if (text.isEmpty) return const [''];
    final rawLines = text.split('\n');
    final result = <String>[];
    for (final line in rawLines) {
      if (line.length <= maxChunkChars) {
        result.add(line);
      } else {
        for (int i = 0; i < line.length; i += maxChunkChars) {
          final end = (i + maxChunkChars < line.length) ? i + maxChunkChars : line.length;
          result.add(line.substring(i, end));
        }
      }
    }
    return result;
  }

  Future<void> _close() async {
    if (widget.file.isFromExternalApp) {
      try {
        const MethodChannel('com.leaflock.app/security')
            .invokeMethod('exitExternalViewer');
      } catch (_) {}
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _saveAsNote() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final l10n = contextL10n(context);

    try {
      final title = FileDecoder.extractTitle(widget.file.name);
      final body = FileDecoder.capBody(widget.file.text);
      final repo = ref.read(notesRepositoryProvider);

      final note = Note.create(
        title: title,
        body: body,
        isChecklistMode: false,
      );

      final savedNote = await repo.insertNote(note);

      if (mounted) {
        AppSnackBar.show(context, message: l10n.noteSavedSuccessfully);
        context.pushReplacement('/note/${savedNote.id}', extra: savedNote);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: l10n.failedToSaveNoteRetry,
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildErrorContent(BuildContext context) {
    final l10n = contextL10n(context);
    final error = widget.file.error;
    switch (error) {
      case FileDecoder.errorTooLarge:
        return ErrorState(
          icon: Icons.folder_off_outlined,
          message: l10n.errorFileTooLarge,
        );
      case FileDecoder.errorBinary:
        return ErrorState(
          icon: Icons.block_outlined,
          message: l10n.errorFileBinary,
        );
      case FileDecoder.errorEmpty:
        return ErrorState(
          icon: Icons.notes_outlined,
          message: l10n.errorFileEmpty,
        );
      case FileDecoder.errorUnreadable:
      default:
        return ErrorState(
          icon: Icons.broken_image_outlined,
          message: l10n.errorFileUnreadable,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = contextL10n(context);
    final dbInitAsync = ref.watch(databaseInitProvider);
    final isRecovery = dbInitAsync.value == DatabaseStatus.recoveryNeeded;

    if (isRecovery) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _close();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.closeAction,
              onPressed: _close,
            ),
            title: Text(
              l10n.databaseRecoveryTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: DatabaseRecoveryScreen(
            onRetry: () => ref.refresh(databaseInitProvider),
          ),
        ),
      );
    }

    final isError = widget.file.error != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.closeAction,
            onPressed: _close,
          ),
          title: Text(
            widget.file.name,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            if (!isError && widget.file.text.isNotEmpty) ...[
              IconButton(
                icon: Icon(
                  _isMonospace ? Icons.font_download : Icons.font_download_outlined,
                ),
                tooltip: _isMonospace
                    ? l10n.variableWidthFontTooltip
                    : l10n.monospaceFontTooltip,
                onPressed: () => setState(() => _isMonospace = !_isMonospace),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                child: FilledButton(
                  onPressed: _isSaving ? null : _saveAsNote,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Text(l10n.saveAsNoteAction),
                ),
              ),
            ],
          ],
        ),
        body: isError
            ? _buildErrorContent(context)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.file.hasInvalidBytes)
                    Container(
                      margin: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      padding: AppSpacing.paddingSm,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                        borderRadius: AppSpacing.borderRadiusSm,
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          AppSpacing.hGapSm,
                          Expanded(
                            child: Text(
                              l10n.undecodedCharactersWarning,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SelectionArea(
                      child: ListView.builder(
                        itemCount: _lines.length,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        itemBuilder: (context, index) {
                          final line = _lines[index];
                          return Text(
                            line.isEmpty ? ' ' : line,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: _isMonospace ? 'monospace' : null,
                              height: 1.4,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
