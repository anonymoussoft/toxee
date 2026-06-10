// Best-effort display-name resolver for Tox friend requests.
//
// Tox friend requests only carry the sender's public key plus the free-form
// request message. There is no dedicated nickname field at the protocol
// level, so when UIKit's `nickname` is empty we try to recover a short handle
// from request messages that look like `alice_here`/`alice here! ...` or
// `alice: ...`. If we cannot infer one safely, callers should fall back to
// the full user ID.

const Set<String> _friendRequestGreetingBlacklist = {
  'hello',
  'hi',
  'hey',
  'greetings',
};

final List<RegExp> _friendRequestNicknamePatterns = <RegExp>[
  RegExp(r'^([A-Za-z0-9_.-]{2,32})\s+here\b', caseSensitive: false),
  RegExp(r'^([A-Za-z0-9_.-]{2,32})\s*[:\-]\s+'),
];

String? inferFriendRequestNicknameFromWording(String? wording) {
  final firstLine = (wording ?? '')
      .trim()
      .split(RegExp(r'[\r\n]'))
      .first
      .trim();
  if (firstLine.isEmpty) return null;

  for (final pattern in _friendRequestNicknamePatterns) {
    final match = pattern.firstMatch(firstLine);
    if (match != null) {
      final candidate = match.group(1)?.trim();
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
  }

  final firstToken = firstLine.split(RegExp(r'\s+')).first.trim();
  final sanitized = firstToken.replaceAll(RegExp(r'^[^\w.-]+|[^\w.-]+$'), '');
  if (sanitized.length < 2 || sanitized.length > 32) return null;
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(sanitized)) return null;
  if (_friendRequestGreetingBlacklist.contains(sanitized.toLowerCase())) {
    return null;
  }
  return null;
}

String resolveFriendRequestDisplayName({
  required String userId,
  String? nickname,
  String? wording,
}) {
  final normalizedNickname = nickname?.trim() ?? '';
  if (normalizedNickname.isNotEmpty && normalizedNickname != userId) {
    return normalizedNickname;
  }
  return inferFriendRequestNicknameFromWording(wording) ?? userId;
}
