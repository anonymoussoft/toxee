// Tox IDs come in two widths: 64-char public key (32 bytes hex), and 76-char full
// address (public key + nospam + checksum). Normalize to public-key form for lookup
// and comparison so the two representations don't fork into separate cache buckets.

/// Normalizes a Tox friend/user ID to 64 characters (public key length).
///
/// Tox friend IDs are 64 characters (public key, 32 bytes in hex).
/// If the ID is 76 characters (full address), extracts the first 64 characters (public key).
/// If longer, extracts only the first 64 characters.
/// If shorter, returns as is (might be a partial ID or different format).
///
/// Parameters:
/// - [id]: The user ID to normalize
///
/// Returns:
/// - Normalized ID (64 characters if original was longer, otherwise unchanged)
String normalizeToxId(String id) {
  final trimmed = id.trim();
  if (trimmed.length == 76) return trimmed.substring(0, 64);
  if (trimmed.length > 64) return trimmed.substring(0, 64);
  return trimmed;
}

/// Canonical Tox public-key extractor.
///
/// Tox public keys are 64 hex chars; full Tox IDs are 76 hex chars
/// (64 pubkey + 8 nospam + 4 checksum). Callers that need a stable
/// identity for routing, history, or friend lookup want the 64-char
/// public-key form regardless of which they were handed.
///
/// Behaviour (preserve historical safety — never throws):
///   * Strip whitespace, lower-case (hex is case-insensitive).
///   * 76 chars → first 64.
///   * 64 chars → returned as-is.
///   * Anything else → returned unchanged (lowercased + trimmed) so
///     non-hex placeholders, group IDs, and short test fixtures still
///     round-trip the way pre-existing call sites expected.
String toToxPublicKey(String input) {
  final cleaned = input.trim().toLowerCase();
  if (cleaned.length == 76) return cleaned.substring(0, 64);
  if (cleaned.length > 64) return cleaned.substring(0, 64);
  return cleaned;
}

/// Compares two Tox IDs for equality after normalization.
/// 
/// This is useful when comparing IDs that might be in different formats
/// (e.g., one is 64 characters, the other is 76 characters, or a 16-char
/// profile prefix vs full public key).
/// 
/// Parameters:
/// - [id1]: First ID to compare
/// - [id2]: Second ID to compare
/// 
/// Returns:
/// - true if the normalized IDs are equal or one is a prefix of the other
///   (for same-account matching when list stores 16-char prefix and service uses 64-char).
bool compareToxIds(String id1, String id2) {
  final n1 = normalizeToxId(id1).trim();
  final n2 = normalizeToxId(id2).trim();
  if (n1 == n2) return true;
  // Allow prefix match strictly for the legacy 16-char profile-prefix vs
  // full 64-char public key case. Any wider prefix window risks collapsing
  // two distinct accounts that happen to share a leading run of hex.
  final longer = n1.length >= n2.length ? n1 : n2;
  final shorter = n1.length < n2.length ? n1 : n2;
  if (shorter.length == 16 && longer.length >= 64) {
    return longer.startsWith(shorter);
  }
  return false;
}

