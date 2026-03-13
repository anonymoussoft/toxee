/// Typed account summary for display and switching; avoids stringly-typed maps.
class AccountSummary {
  const AccountSummary({
    required this.toxId,
    required this.nickname,
    required this.statusMessage,
    this.avatarPath,
    this.lastLoginTime,
  });

  final String toxId;
  final String nickname;
  final String statusMessage;
  final String? avatarPath;
  final DateTime? lastLoginTime;

  factory AccountSummary.fromMap(Map<String, String> map) {
    return AccountSummary(
      toxId: map['toxId'] ?? '',
      nickname: map['nickname'] ?? '',
      statusMessage: map['statusMessage'] ?? '',
      avatarPath: map['avatarPath'],
      lastLoginTime: map['lastLoginTime'] == null
          ? null
          : DateTime.tryParse(map['lastLoginTime']!),
    );
  }

  Map<String, String> toMap() => {
        'toxId': toxId,
        'nickname': nickname,
        'statusMessage': statusMessage,
        if (avatarPath != null && avatarPath!.isNotEmpty) 'avatarPath': avatarPath!,
        if (lastLoginTime != null) 'lastLoginTime': lastLoginTime!.toIso8601String(),
      };
}
