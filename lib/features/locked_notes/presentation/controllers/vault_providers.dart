import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../core/crypto/kdf_service.dart';
import '../../../../core/crypto/recovery_key_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../notes/data/notes_repository.dart';
import '../../../notes/domain/note.dart';
import '../../../notes/presentation/controllers/notes_providers.dart';

final kdfServiceProvider = Provider<KdfService>((ref) {
  return NativeKdfService();
});

final vaultServiceProvider = Provider<VaultService>((ref) {
  final appDb = ref.watch(appDatabaseProvider);
  final kdfService = ref.watch(kdfServiceProvider);
  return VaultService(
    appDatabase: appDb,
    kdfService: kdfService,
    elapsedRealtimeProvider: () async {
      try {
        const channel = MethodChannel('com.privacynotes.app/security');
        final res = await channel.invokeMethod<int>('getElapsedRealtime');
        return res ?? DateTime.now().millisecondsSinceEpoch;
      } catch (_) {
        return DateTime.now().millisecondsSinceEpoch;
      }
    },
  );
});

class VaultState {
  final bool hasVault;
  final bool hasRecoveryKey;
  final bool isUnlocked;
  final CredentialType credentialType;
  final int failedAttempts;
  final int remainingLockoutSeconds;
  final int recoveryFailedAttempts;
  final int remainingRecoveryLockoutSeconds;
  final String autoLockTimeout;
  final bool isDeriving;
  final String? errorMessage;

  const VaultState({
    this.hasVault = false,
    this.hasRecoveryKey = false,
    this.isUnlocked = false,
    this.credentialType = CredentialType.pin,
    this.failedAttempts = 0,
    this.remainingLockoutSeconds = 0,
    this.recoveryFailedAttempts = 0,
    this.remainingRecoveryLockoutSeconds = 0,
    this.autoLockTimeout = 'background',
    this.isDeriving = false,
    this.errorMessage,
  });

  VaultState copyWith({
    bool? hasVault,
    bool? hasRecoveryKey,
    bool? isUnlocked,
    CredentialType? credentialType,
    int? failedAttempts,
    int? remainingLockoutSeconds,
    int? recoveryFailedAttempts,
    int? remainingRecoveryLockoutSeconds,
    String? autoLockTimeout,
    bool? isDeriving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VaultState(
      hasVault: hasVault ?? this.hasVault,
      hasRecoveryKey: hasRecoveryKey ?? this.hasRecoveryKey,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      credentialType: credentialType ?? this.credentialType,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      remainingLockoutSeconds: remainingLockoutSeconds ?? this.remainingLockoutSeconds,
      recoveryFailedAttempts: recoveryFailedAttempts ?? this.recoveryFailedAttempts,
      remainingRecoveryLockoutSeconds: remainingRecoveryLockoutSeconds ?? this.remainingRecoveryLockoutSeconds,
      autoLockTimeout: autoLockTimeout ?? this.autoLockTimeout,
      isDeriving: isDeriving ?? this.isDeriving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class VaultNotifier extends ChangeNotifier {
  final VaultService _vaultService;

  VaultState _state = const VaultState();
  Timer? _lockoutTimer;
  Timer? _recoveryLockoutTimer;
  DateTime? _lastBackgroundedTime;
  bool _isDisposed = false;

  VaultNotifier({
    required this._vaultService,
  }) {
    _state = _state.copyWith(
      isUnlocked: _vaultService.isUnlocked,
    );
    loadVaultState();
  }

  VaultState get state => _state;
  bool get hasVault => _state.hasVault;
  bool get hasRecoveryKey => _state.hasRecoveryKey;
  bool get isUnlocked => _state.isUnlocked;
  CredentialType get credentialType => _state.credentialType;
  Uint8List? get vaultKey => _vaultService.vaultKey;

  @override
  void dispose() {
    _isDisposed = true;
    _lockoutTimer?.cancel();
    _recoveryLockoutTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> loadVaultState() async {
    try {
      final exists = await _vaultService.hasVault();
      CredentialType credType = CredentialType.pin;
      bool recExists = false;
      if (exists) {
        final meta = await _vaultService.getVaultMetadata();
        if (meta != null) {
          credType = meta.credentialType;
          recExists = meta.hasRecoveryKey;
        }
      }

      final failures = await _vaultService.getFailedAttempts();
      final lockout = await _vaultService.getRemainingLockoutSeconds();
      final recFailures = await _vaultService.getRecoveryFailedAttempts();
      final recLockout = await _vaultService.getRemainingRecoveryLockoutSeconds();
      final autoLock = await _vaultService.getAutoLockTimeout();

      _state = _state.copyWith(
        hasVault: exists,
        hasRecoveryKey: recExists,
        isUnlocked: _vaultService.isUnlocked,
        credentialType: credType,
        failedAttempts: failures,
        remainingLockoutSeconds: lockout,
        recoveryFailedAttempts: recFailures,
        remainingRecoveryLockoutSeconds: recLockout,
        autoLockTimeout: autoLock,
      );

      if (lockout > 0) {
        _startLockoutCountdown(lockout);
      }
      if (recLockout > 0) {
        _startRecoveryLockoutCountdown(recLockout);
      }

      notifyListeners();
    } catch (_) {}
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    int current = seconds;
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      current--;
      if (current <= 0) {
        timer.cancel();
        _state = _state.copyWith(remainingLockoutSeconds: 0);
        notifyListeners();
      } else {
        _state = _state.copyWith(remainingLockoutSeconds: current);
        notifyListeners();
      }
    });
  }

  void _startRecoveryLockoutCountdown(int seconds) {
    _recoveryLockoutTimer?.cancel();
    int current = seconds;
    _recoveryLockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      current--;
      if (current <= 0) {
        timer.cancel();
        _state = _state.copyWith(remainingRecoveryLockoutSeconds: 0);
        notifyListeners();
      } else {
        _state = _state.copyWith(remainingRecoveryLockoutSeconds: current);
        notifyListeners();
      }
    });
  }

  Future<void> setupVault({
    required String secret,
    required CredentialType credentialType,
    String? recoveryKeyString,
    int? iterations,
  }) async {
    _state = _state.copyWith(isDeriving: true, clearError: true);
    notifyListeners();

    try {
      if (iterations != null) {
        await _vaultService.setupVault(
          secret: secret,
          credentialType: credentialType,
          recoveryKeyString: recoveryKeyString,
          iterations: iterations,
        );
      } else {
        await _vaultService.setupVault(
          secret: secret,
          credentialType: credentialType,
          recoveryKeyString: recoveryKeyString,
        );
      }

      _state = _state.copyWith(
        hasVault: true,
        hasRecoveryKey: recoveryKeyString != null,
        isUnlocked: true,
        credentialType: credentialType,
        failedAttempts: 0,
        remainingLockoutSeconds: 0,
        recoveryFailedAttempts: 0,
        remainingRecoveryLockoutSeconds: 0,
        isDeriving: false,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        isDeriving: false,
        errorMessage: 'Failed to set up vault: $e',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createOrUpdateRecoveryKey({
    required String currentSecret,
    required String recoveryKeyString,
  }) async {
    _state = _state.copyWith(isDeriving: true, clearError: true);
    notifyListeners();

    try {
      await _vaultService.createOrUpdateRecoveryKey(
        currentSecret: currentSecret,
        recoveryKeyString: recoveryKeyString,
      );
      _state = _state.copyWith(
        hasRecoveryKey: true,
        recoveryFailedAttempts: 0,
        remainingRecoveryLockoutSeconds: 0,
        isDeriving: false,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        isDeriving: false,
        errorMessage: e is VaultAuthException ? e.message : 'Failed to update recovery key: $e',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> recoverVault({
    required String recoveryKeyString,
    required String newSecret,
    required CredentialType newCredentialType,
    int? iterations,
  }) async {
    _state = _state.copyWith(isDeriving: true, clearError: true);
    notifyListeners();

    try {
      if (iterations != null) {
        await _vaultService.recoverVault(
          recoveryKeyString: recoveryKeyString,
          newSecret: newSecret,
          newCredentialType: newCredentialType,
          iterations: iterations,
        );
      } else {
        await _vaultService.recoverVault(
          recoveryKeyString: recoveryKeyString,
          newSecret: newSecret,
          newCredentialType: newCredentialType,
        );
      }

      _state = _state.copyWith(
        isUnlocked: true,
        credentialType: newCredentialType,
        failedAttempts: 0,
        remainingLockoutSeconds: 0,
        recoveryFailedAttempts: 0,
        remainingRecoveryLockoutSeconds: 0,
        isDeriving: false,
      );
      notifyListeners();
    } on VaultLockoutException catch (e) {
      _startRecoveryLockoutCountdown(e.remainingSeconds);
      _state = _state.copyWith(
        isDeriving: false,
        remainingRecoveryLockoutSeconds: e.remainingSeconds,
        errorMessage: e.toString(),
      );
      notifyListeners();
      rethrow;
    } on RecoveryKeyAuthException catch (e) {
      final lockout = await _vaultService.getRemainingRecoveryLockoutSeconds();
      if (lockout > 0) {
        _startRecoveryLockoutCountdown(lockout);
      }
      _state = _state.copyWith(
        isDeriving: false,
        remainingRecoveryLockoutSeconds: lockout,
        errorMessage: e.message,
      );
      notifyListeners();
      rethrow;
    } catch (e) {
      _state = _state.copyWith(
        isDeriving: false,
        errorMessage: e.toString(),
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> unlockVault(String secret) async {
    _state = _state.copyWith(isDeriving: true, clearError: true);
    notifyListeners();

    try {
      await _vaultService.unlockVault(secret);
      _state = _state.copyWith(
        isUnlocked: true,
        failedAttempts: 0,
        remainingLockoutSeconds: 0,
        isDeriving: false,
      );
      notifyListeners();
    } on VaultPlatformException catch (e) {
      _state = _state.copyWith(
        isDeriving: false,
        errorMessage: e.message,
      );
      notifyListeners();
      rethrow;
    } on VaultLockoutException catch (e) {
      _startLockoutCountdown(e.remainingSeconds);
      _state = _state.copyWith(
        isDeriving: false,
        remainingLockoutSeconds: e.remainingSeconds,
        errorMessage: e.toString(),
      );
      notifyListeners();
      rethrow;
    } on VaultAuthException catch (e) {
      final lockout = await _vaultService.getRemainingLockoutSeconds();
      if (lockout > 0) {
        _startLockoutCountdown(lockout);
      }
      _state = _state.copyWith(
        isDeriving: false,
        remainingLockoutSeconds: lockout,
        errorMessage: e.message,
      );
      notifyListeners();
      rethrow;
    } catch (e) {
      _state = _state.copyWith(
        isDeriving: false,
        errorMessage: 'An unexpected error occurred: $e',
      );
      notifyListeners();
      rethrow;
    }
  }

  void lockVault() {
    _vaultService.lockVault();
    _state = _state.copyWith(isUnlocked: false);
    notifyListeners();
  }

  Future<void> changeSecret({
    required String currentSecret,
    required String newSecret,
    required CredentialType newCredentialType,
    int? iterations,
  }) async {
    _state = _state.copyWith(isDeriving: true, clearError: true);
    notifyListeners();

    try {
      if (iterations != null) {
        await _vaultService.changeSecret(
          currentSecret: currentSecret,
          newSecret: newSecret,
          newCredentialType: newCredentialType,
          iterations: iterations,
        );
      } else {
        await _vaultService.changeSecret(
          currentSecret: currentSecret,
          newSecret: newSecret,
          newCredentialType: newCredentialType,
        );
      }

      _state = _state.copyWith(
        credentialType: newCredentialType,
        isDeriving: false,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(
        isDeriving: false,
        errorMessage: e is VaultAuthException || e is VaultPlatformException ? e.toString() : 'Failed to change secret: $e',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resetVault() async {
    await _vaultService.resetVault();
    _lockoutTimer?.cancel();
    _recoveryLockoutTimer?.cancel();
    _state = const VaultState(
      hasVault: false,
      hasRecoveryKey: false,
      isUnlocked: false,
      credentialType: CredentialType.pin,
      failedAttempts: 0,
      remainingLockoutSeconds: 0,
      recoveryFailedAttempts: 0,
      remainingRecoveryLockoutSeconds: 0,
    );
    notifyListeners();
  }

  Future<void> setAutoLockTimeout(String timeout) async {
    await _vaultService.setAutoLockTimeout(timeout);
    _state = _state.copyWith(autoLockTimeout: timeout);
    notifyListeners();
  }

  // Lifecycle handling for auto-lock (D7)
  void onAppPaused() {
    _lastBackgroundedTime = _vaultService.clock();
    if (_state.autoLockTimeout == 'background' || _state.autoLockTimeout == 'immediately') {
      lockVault();
    }
  }

  void onAppResumed() {
    if (!isUnlocked || _lastBackgroundedTime == null) return;
    final now = _vaultService.clock();
    final elapsed = now.difference(_lastBackgroundedTime!);
    _lastBackgroundedTime = null;

    int timeoutSeconds = 0;
    switch (_state.autoLockTimeout) {
      case '1_min':
        timeoutSeconds = 60;
        break;
      case '5_min':
        timeoutSeconds = 300;
        break;
      case '15_min':
        timeoutSeconds = 900;
        break;
      default:
        timeoutSeconds = 0;
    }

    if (timeoutSeconds > 0 && elapsed.inSeconds >= timeoutSeconds) {
      lockVault();
    }
  }
}

final vaultProvider = ChangeNotifierProvider<VaultNotifier>((ref) {
  final vaultService = ref.watch(vaultServiceProvider);
  return VaultNotifier(
    vaultService: vaultService,
  );
});

// Locked Notes List Notifier
class LockedNotesNotifier extends ChangeNotifier {
  final NotesRepository _notesRepository;
  final VaultNotifier _vaultNotifier;

  List<Note> _notes = const [];
  bool _isLoading = false;
  String? _errorMessage;

  LockedNotesNotifier({
    required this._notesRepository,
    required this._vaultNotifier,
  }) {
    _vaultNotifier.addListener(_onVaultChanged);
    loadLockedNotes();
  }

  void _onVaultChanged() {
    if (_vaultNotifier.isUnlocked) {
      loadLockedNotes();
    } else {
      _notes = const [];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _vaultNotifier.removeListener(_onVaultChanged);
    super.dispose();
  }

  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadLockedNotes() async {
    final key = _vaultNotifier.vaultKey;
    if (key == null) {
      _notes = const [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _notes = await _notesRepository.getLockedNotes(key);
    } catch (e) {
      _errorMessage = 'Failed to decrypt locked notes.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> unlockNote(String noteId) async {
    final key = _vaultNotifier.vaultKey;
    if (key == null) return;
    await _notesRepository.unlockNote(noteId, key);
    await loadLockedNotes();
  }

  Future<void> deleteLockedNotePermanently(String noteId) async {
    await _notesRepository.deleteLockedNotePermanently(noteId);
    await loadLockedNotes();
  }
}

final lockedNotesProvider = ChangeNotifierProvider.autoDispose<LockedNotesNotifier>((ref) {
  final notesRepo = ref.watch(notesRepositoryProvider);
  final vaultNotifier = ref.watch(vaultProvider);
  return LockedNotesNotifier(
    notesRepository: notesRepo,
    vaultNotifier: vaultNotifier,
  );
});
