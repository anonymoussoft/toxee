// Seed-data definitions for the product-screenshot pipeline
// (capture_product_screenshots.dart): personas, the scripted conversations,
// and host-side generated media (photo PNGs + a tiny real PDF).
//
// Everything here is DATA, deliberately separated from the driver so the
// dialogue can be re-written without touching orchestration. The dialogue is
// in English (the product page's primary locale) with light emoji — it reads
// as a real weekend-hike plan, which matches the seeded group.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// One seeded account. [instance] is the launcher instance name (ShotA…),
/// [nickname] the realistic display name the persona registers with —
/// allowed because `l3_register_account` records the SEED-ACCOUNT MARKER
/// (identity-by-construction), not a nickname allowlist.
class Persona {
  const Persona({
    required this.instance,
    required this.nickname,
    required this.statusMessage,
  });

  final String instance;
  final String nickname;
  final String statusMessage;
}

const personaA = Persona(
  instance: 'ShotA',
  nickname: 'Mia',
  statusMessage: 'Hiking, coffee, and P2P chat',
);
const personaB = Persona(
  instance: 'ShotB',
  nickname: 'Alex Chen',
  statusMessage: 'On the trail somewhere',
);
const personaC = Persona(
  instance: 'ShotC',
  nickname: 'Sofia 🌸',
  statusMessage: 'Probably reading',
);
const personaD = Persona(
  instance: 'ShotD',
  nickname: 'Kenta 健太',
  statusMessage: '東京 ⇄ everywhere',
);

const allPersonas = [personaA, personaB, personaC, personaD];

/// Group seeded by ShotA (private NGC + invite — same-host reliable).
const groupName = 'Weekend Hikers 🏔';

/// One scripted line. [fromA] true = ShotA sends, false = the peer sends.
class ScriptLine {
  const ScriptLine(this.fromA, this.text);
  final bool fromA;
  final String text;
}

/// ShotA ↔ ShotB hero conversation. Mixed directions, emoji, and two
/// anchor lines used by the media/reply steps:
///   - [bReplyAnchor] is the B line ShotA quotes via l3_reply_text (the
///     quote bubble renders sender-side only — plan F14);
///   - the photo + PDF are sent by B right after [bPhotoLeadIn] so the
///     image bubble is INBOUND on ShotA (extension-classified — plan F6).
const bReplyAnchor = 'Lake trail this Saturday? The larches just turned 🍂';
const bPhotoLeadIn = 'Found the view from last month — look at this';

// Ordered so the visually rich beats (photo thumbnail, PDF tile, quoted
// reply) land in the BOTTOM ~7 rows — the chat pane shows roughly the last
// 8-9 bubbles at 1280×800, and the freshen line adds one more below.
const conversationAB = [
  ScriptLine(false, 'Hey Mia! Made it back from Patagonia 🎒'),
  ScriptLine(true, 'Alex!! Welcome back. How was the W trek?'),
  ScriptLine(false, 'Unreal. Knees are filing a formal complaint though'),
  ScriptLine(true, 'Haha, worth it 😄'),
  ScriptLine(false, bReplyAnchor),
  // ShotA's QUOTED reply to bReplyAnchor is sent by the driver between
  // these lines via l3_reply_text (not a plain ScriptLine).
  ScriptLine(false, 'Trailhead at 7am, back before the rain hits'),
  ScriptLine(true, 'Deal. I will bring the good thermos ☕'),
  ScriptLine(false, bPhotoLeadIn),
  // <- B sends lake-trail.png here (driver step)
  ScriptLine(true, 'Okay WOW. That is the wallpaper now 😍'),
  // <- B sends Trip-Plan.pdf here (driver step)
  ScriptLine(true, 'Got it. See you Saturday 🥾'),
];

/// AB history size when fully seeded: 10 texts + 1 quoted reply + 2 files.
const conversationABSeededCount = 13;

/// ShotA's quoted reply (sent via l3_reply_text against [bReplyAnchor]).
const aQuotedReply = 'Which trailhead — north loop or the lakeside start?';

/// ShotA ↔ ShotC (Sofia). Short + warm; her conversation stays UNOPENED
/// during the scene walk so her unread badge survives (plan F7), and she is
/// the recv-opt mute demo (opt=1).
const conversationAC = [
  ScriptLine(false, 'Mia! I finished the book you lent me 📖'),
  ScriptLine(true, 'Already?! Okay, verdict?'),
  ScriptLine(false, 'Cried twice on the train. 10/10'),
  ScriptLine(true, 'Knew it. Coffee this week and we debrief ☕'),
];

/// ShotA ↔ ShotD (Kenta). Multilingual flavor; also stays unopened.
const conversationAD = [
  ScriptLine(false, 'Just landed in Tokyo! 東京に着いたよ 🗼'),
  ScriptLine(true, 'Safe travels!! Send photos of everything'),
  ScriptLine(false, 'The convenience stores alone deserve an album'),
];

/// Group chatter — (senderInstance, text). Sent in order.
const groupScript = [
  ('ShotA', 'Made us a group for Saturday 🏔'),
  ('ShotB', 'Excellent. 7am at the north lot?'),
  ('ShotC', 'In! Bringing trail mix 🥜'),
  ('ShotA', '7am works. Weather says clear until 3pm'),
  ('ShotB', 'I have the map + first aid kit'),
  ('ShotC', 'Someone please bring a real camera 📷'),
  ('ShotA', 'On it. Lakeside lunch at the halfway point?'),
  ('ShotB', 'Approved 🙌'),
];

/// Fresh "just now" lines injected at every boot BEFORE any conversation is
/// opened (activePeerId == null → unread increments). C/D badges survive the
/// whole scene walk; B's clears when scene 01 opens the hero chat.
const freshenB = [
  'Forecast update: still clear for Saturday ☀️',
];
const freshenC = [
  'Found the sequel at the bookshop today!! 📚',
  'No spoilers but the first chapter is ALREADY too much',
];
const freshenD = ['Shibuya at night is something else 🌃'];

/// Search query used by scene 12 — guaranteed by the AB script above.
const searchQuery = 'trailhead';

// ───────────────────────── generated media ─────────────────────────

/// Generate the inbound "photo" — a stylized mountain-lake scene (gradient
/// sky, sun, ridgelines, water) at 1200×800. Pure-procedural: no copyright,
/// deterministic output, looks intentional as a thumbnail. Returns the path.
Future<String> ensureLakeTrailPng(Directory mediaDir) async {
  final file = File('${mediaDir.path}/lake-trail.png');
  if (await file.exists() && (await file.length()) > 0) return file.path;
  await mediaDir.create(recursive: true);

  const w = 1200, h = 800;
  final canvas = img.Image(width: w, height: h);

  // Sky: dusk gradient (deep indigo → warm peach at the horizon line).
  const horizon = 520;
  for (var y = 0; y < horizon; y++) {
    final t = y / horizon;
    final r = (30 + 225 * math.pow(t, 2.2)).round();
    final g = (41 + 130 * math.pow(t, 2.0)).round();
    final b = (84 + 70 * t).round();
    for (var x = 0; x < w; x++) {
      canvas.setPixelRgb(x, y, r, g, b);
    }
  }
  // Sun disc with soft halo.
  const sunX = 850, sunY = 360, sunR = 46;
  for (var y = sunY - 120; y < sunY + 120; y++) {
    for (var x = sunX - 120; x < sunX + 120; x++) {
      if (x < 0 || y < 0 || x >= w || y >= horizon) continue;
      final d = math.sqrt(
        (x - sunX) * (x - sunX) + (y - sunY) * (y - sunY).toDouble(),
      );
      if (d < sunR) {
        canvas.setPixelRgb(x, y, 255, 236, 200);
      } else if (d < 120) {
        final p = canvas.getPixel(x, y);
        final mix = (1 - (d - sunR) / (120 - sunR)) * 0.35;
        canvas.setPixelRgb(
          x,
          y,
          (p.r + (255 - p.r) * mix).round(),
          (p.g + (236 - p.g) * mix).round(),
          (p.b + (200 - p.b) * mix).round(),
        );
      }
    }
  }
  // Two mountain ridgelines (far: hazy slate; near: deep pine).
  int ridgeFar(int x) =>
      (300 +
              90 * math.sin(x / 170) +
              45 * math.sin(x / 61 + 2.1) +
              18 * math.sin(x / 23 + 0.7))
          .round();
  int ridgeNear(int x) =>
      (430 +
              70 * math.sin(x / 120 + 4.0) +
              35 * math.sin(x / 47 + 1.2) +
              12 * math.sin(x / 17 + 3.3))
          .round();
  for (var x = 0; x < w; x++) {
    final f = ridgeFar(x);
    for (var y = f; y < horizon; y++) {
      final fade = ((y - f) / (horizon - f) * 24).round();
      canvas.setPixelRgb(x, y, 71 + fade, 85 + fade, 105 + fade);
    }
    final n = ridgeNear(x);
    for (var y = n; y < horizon; y++) {
      canvas.setPixelRgb(x, y, 22, 51, 47);
    }
  }
  // Water: vertical reflection gradient with sun glint + ripple banding.
  for (var y = horizon; y < h; y++) {
    final t = (y - horizon) / (h - horizon);
    for (var x = 0; x < w; x++) {
      var r = (40 + 50 * (1 - t)).round();
      var g = (70 + 60 * (1 - t)).round();
      var b = (110 + 50 * (1 - t)).round();
      final ripple = math.sin(y / 3.0 + x / 90.0);
      if ((x - sunX).abs() < 60 + 90 * t && ripple > 0.55) {
        r += 90;
        g += 70;
        b += 40;
      }
      canvas.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }

  await file.writeAsBytes(img.encodePng(canvas));
  print('[seed-media] generated ${file.path}');
  return file.path;
}

/// Generate a tiny but STRUCTURALLY VALID single-page PDF ("Trip Plan") so
/// the seeded file bubble is honest — opening it shows a real page instead
/// of a broken file. Plain Latin-1 content, no compression.
Future<String> ensureTripPlanPdf(Directory mediaDir) async {
  final file = File('${mediaDir.path}/Trip-Plan.pdf');
  if (await file.exists() && (await file.length()) > 0) return file.path;
  await mediaDir.create(recursive: true);

  const content = 'BT /F1 24 Tf 72 720 Td (Weekend Hikers - Trip Plan) Tj '
      '0 -36 Td /F1 14 Tf (07:00  Meet at the north lot) Tj '
      '0 -22 Td (07:15  Lakeside start, counter-clockwise loop) Tj '
      '0 -22 Td (12:00  Lunch at the halfway point) Tj '
      '0 -22 Td (15:00  Back before the rain) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buf = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buf.length);
    buf.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buf.length;
  buf.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final off in offsets) {
    buf.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  buf.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  await file.writeAsString(buf.toString());
  print('[seed-media] generated ${file.path}');
  return file.path;
}
