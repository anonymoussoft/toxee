#!/usr/bin/env python3
"""Audit native Dart* FFI signatures vs the generated Dart binding (ABI truth).

A mismatch in arg COUNT (or pointer-vs-scalar) is a latent SIGSEGV: the call
compiles but misaligns args at runtime (the mute DartSetC2CReceiveMessageOpt bug).
"""
import re, glob, os, sys

REPO = "/Users/bin.gao/chat-uikit/toxee"
GEN = os.path.join(REPO, "third_party/tencent_cloud_chat_sdk/lib/native_im/bindings/native_imsdk_bindings_generated.dart")
NATIVE_GLOB = os.path.join(REPO, "third_party/tim2tox/ffi/dart_compat_*.cpp")

def norm(s):
    return re.sub(r"\s+", " ", s).strip()

# --- 1. Parse the generated binding: name -> list of native arg types ---
gen_txt = open(GEN).read()
gen = {}
# _lookup<ffi.NativeFunction<RET Function(ARGS)>>('DartName')
for m in re.finditer(r"_lookup<\s*ffi\.NativeFunction<\s*(.*?)>>\(\s*'(\w+)'\s*\)", gen_txt, re.S):
    sig, name = m.group(1), m.group(2)
    if not name.startswith("Dart"):
        continue
    fm = re.search(r"Function\((.*)\)\s*$", norm(sig))
    if not fm:
        continue
    args_str = fm.group(1).strip()
    if not args_str:
        gen[name] = []
        continue
    # split top-level commas (not inside <>)
    args, depth, cur = [], 0, ""
    for ch in args_str:
        if ch == '<': depth += 1
        elif ch == '>': depth -= 1
        if ch == ',' and depth == 0:
            args.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip(): args.append(cur.strip())
    gen[name] = args

def gen_kind(t):
    t = t.lower()
    if "pointer" in t: return "ptr"
    if "int" in t or "uint" in t or "long" in t or "char" == t: return "int"
    if "double" in t or "float" in t: return "flt"
    return t

# --- 2. Parse native .cpp: name -> list of arg types ---
nat = {}
for f in glob.glob(NATIVE_GLOB):
    txt = open(f).read()
    # int DartName( ARGS ) {   (args may span lines)
    for m in re.finditer(r"\bint\s+(Dart\w+)\s*\(([^)]*)\)\s*\{", txt, re.S):
        name, args_str = m.group(1), norm(m.group(2))
        if name in nat:
            continue  # first definition wins
        if args_str in ("", "void"):
            nat[name] = []
            continue
        args = [a.strip() for a in args_str.split(",")]
        nat[name] = args

def nat_kind(a):
    a = a.lower()
    if "*" in a: return "ptr"
    if "int" in a or "long" in a or "unsigned" in a or "size_t" in a: return "int"
    if "double" in a or "float" in a: return "flt"
    return a

# --- 3. Compare ---
mismatches = []
both = sorted(set(gen) & set(nat))
for name in both:
    gk = [gen_kind(t) for t in gen[name]]
    nk = [nat_kind(a) for a in nat[name]]
    if len(gk) != len(nk):
        mismatches.append((name, "ARGCOUNT", f"binding={len(gk)}{gk} native={len(nk)}{nk}"))
    elif gk != nk:
        # only flag ptr-vs-scalar swaps (the dangerous kind)
        diff = [(i, gk[i], nk[i]) for i in range(len(gk)) if gk[i] != nk[i]]
        dangerous = [d for d in diff if "ptr" in (d[1], d[2])]
        if dangerous:
            mismatches.append((name, "TYPE", f"binding={gk} native={nk} diff={diff}"))

print(f"Dart* in binding: {len(gen)} | in native: {len(nat)} | compared: {len(both)}")
print(f"=== MISMATCHES: {len(mismatches)} ===")
for name, kind, detail in mismatches:
    print(f"[{kind}] {name}: {detail}")

only_gen = sorted(set(gen) - set(nat))
print(f"\n=== in binding, native def not found ({len(only_gen)}) (may be in headers/other) ===")
print(", ".join(only_gen[:40]))
