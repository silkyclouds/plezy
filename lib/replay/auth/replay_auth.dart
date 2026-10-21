/// The result of signing in to a broadcaster: opaque to the app, meaningful to its provider.
class ReplaySession {
  /// Shown in settings, usually the e-mail address the user signed in with.
  final String accountLabel;

  /// Tokens and identifiers the provider needs to call the broadcaster as this user.
  final Map<String, String> values;
  final DateTime? expiresAt;

  const ReplaySession({required this.accountLabel, required this.values, this.expiresAt});

  bool isExpiredAt(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  Map<String, dynamic> toJson() => {
    'accountLabel': accountLabel,
    'values': values,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };

  factory ReplaySession.fromJson(Map<String, dynamic> json) => ReplaySession(
    accountLabel: json['accountLabel'] as String? ?? '',
    values: {for (final e in (json['values'] as Map? ?? const {}).entries) e.key.toString(): e.value.toString()},
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
  );
}

enum ReplayAuthFailure { invalidCredentials, rateLimited, captchaRequired, network, rejected }

/// Signing in failed. [message] is the broadcaster's own wording when it gave one.
class ReplayAuthException implements Exception {
  final ReplayAuthFailure reason;
  final String? message;

  const ReplayAuthException(this.reason, {this.message});

  @override
  String toString() => 'Sign-in failed: ${reason.name}${message == null ? '' : ' ($message)'}';
}

/// Turns a user's credentials into a [ReplaySession]. The password is never kept: only the session is.
abstract interface class ReplayAuthenticator {
  Future<ReplaySession> signIn({required String login, required String password});

  /// A fresh session from an expired one, or a [ReplayAuthException] when the user has to sign in again.
  Future<ReplaySession> refresh(ReplaySession session);
}

/// Implemented by providers whose broadcaster has user accounts.
abstract interface class ReplayAccountSupport {
  ReplayAuthenticator get authenticator;

  /// Makes the provider act as the signed-in user, or anonymously when [session] is null.
  void useSession(ReplaySession? session);

  /// Called with the new session each time the provider renews it by itself, so it can be stored.
  /// Without it a rotated refresh token would be lost and the user signed out at the next launch.
  set onSessionRenewed(void Function(ReplaySession session)? listener);
}
