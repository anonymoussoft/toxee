/// Tox utility functions for handling user IDs
/// 
/// Tox IDs can be in two formats:
/// - 64 characters: Public key (32 bytes in hex)
/// - 76 characters: Full address (64 bytes public key + 4 bytes nospam + 2 bytes checksum)
/// 
/// This utility provides functions to normalize IDs for consistent comparison and lookup.

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
  return trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed;
}

/// Compares two Tox IDs for equality after normalization.
/// 
/// This is useful when comparing IDs that might be in different formats
/// (e.g., one is 64 characters, the other is 76 characters).
/// 
/// Parameters:
/// - [id1]: First ID to compare
/// - [id2]: Second ID to compare
/// 
/// Returns:
/// - true if the normalized IDs are equal, false otherwise
bool compareToxIds(String id1, String id2) {
  return normalizeToxId(id1) == normalizeToxId(id2);
}

