#!/usr/bin/env python3
"""Validate the NextShelf iOS project without Xcode.

Checks (no compiler available on this Linux VM):
  1. project.pbxproj: balanced braces/parens, unique IDs, every
     fileRef resolves to a real file, Sources/Resources/Frameworks
     phases complete.
  2. Info.plist parses as a plist.
  3. Every Color("…") / Image("…") referenced in Swift exists in the
     asset catalog; every asset is referenced or is an icon/launcher.
  4. Swift files: balanced (), {}, [] (comment/string aware, rough),
     no placeholder markers, no secrets.
  5. No credential/secret strings anywhere in the project.

Exit code 0 = all checks pass.
"""
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "NextShelf"
PBX = ROOT / "NextShelf.xcodeproj" / "project.pbxproj"
swift_files = sorted(APP.rglob("*.swift"))

errors, warnings = [], []


def check(cond, msg):
    if not cond:
        errors.append(msg)


# ---------------------------------------------------------------- 1. pbxproj
text = PBX.read_text()
check(text.count("{") == text.count("}"), "pbxproj: unbalanced braces")
check(text.count("(") == text.count(")"), "pbxproj: unbalanced parens")

ids = re.findall(r"^\t\t([0-9A-F]{24}) \S", text, re.MULTILINE)
check(len(ids) == len(set(ids)), f"pbxproj: duplicate object IDs ({len(ids)} vs {len(set(ids))})")

# Every fileRef path must exist (paths are relative to the group dir).
filerefs = re.findall(
    r"isa = PBXFileReference;.*?path = ([^;]+);", text, re.DOTALL)
for p in filerefs:
    p = p.strip().strip('"')
    if p.startswith("System/") or p == "NextShelf.app":
        continue
    # Resolve: file name within the app dir tree.
    found = list(APP.rglob(p))
    check(bool(found), f"pbxproj: fileRef '{p}' not found under NextShelf/")

# Sources phase must contain every .swift file (slice the section: the
# PBXBuildFile lines carry the same "in Sources" comment).
src_section = text.split("Begin PBXSourcesBuildPhase section")[1].split(
    "End PBXSourcesBuildPhase section")[0]
sources = re.findall(r"/\* (\S+\.swift) in Sources \*/", src_section)
check(sorted(sources) == sorted(f.name for f in swift_files),
      f"pbxproj: Sources phase mismatch: {sorted(set(sources) ^ {f.name for f in swift_files})}")
check("Assets.xcassets in Resources" in text, "pbxproj: Assets missing from Resources")
check("WebKit.framework in Frameworks" in text, "pbxproj: WebKit missing from Frameworks")
check("INFOPLIST_FILE = NextShelf/Info.plist" in text, "pbxproj: INFOPLIST_FILE wrong")
check("IPHONEOS_DEPLOYMENT_TARGET = 17.0" in text, "pbxproj: deployment target wrong")
check("com.nextshelf.app" in text, "pbxproj: bundle id missing")
check("PRODUCT_BUNDLE_IDENTIFIER" in text, "pbxproj: no bundle id setting")

# ---------------------------------------------------------------- 2. Info.plist
try:
    plist = plistlib.loads((APP / "Info.plist").read_bytes())
    check(plist.get("CFBundleDisplayName") == "NextShelf", "Info.plist: display name")
    check("UILaunchScreen" in plist, "Info.plist: no UILaunchScreen")
except Exception as e:  # noqa
    errors.append(f"Info.plist does not parse: {e}")

# ---------------------------------------------------------------- 3. asset references
catalog = APP / "Assets.xcassets"
asset_names = {p.parent.name.split(".")[0] for p in catalog.rglob("Contents.json")
               if p.parent != catalog}
swift_text = "\n".join(f.read_text() for f in swift_files)
for name in sorted(set(re.findall(r'Color\("([^"]+)"\)', swift_text))):
    check(name in asset_names, f"Swift references missing color asset '{name}'")
for name in sorted(set(re.findall(r'Image\("([^"]+)"\)', swift_text))):
    check(name in asset_names, f"Swift references missing image asset '{name}'")
for name in ("LaunchLogo", "Paper", "AppIcon", "AccentColor"):
    check(name in asset_names, f"asset catalog missing '{name}'")
# AppIcon completeness
icon = json.loads((catalog / "AppIcon.appiconset" / "Contents.json").read_text())
for img in icon["images"]:
    check((catalog / "AppIcon.appiconset" / img["filename"]).exists(),
          f"AppIcon missing {img['filename']}")
    if img["size"] == "1024x1024":
        from PIL import Image
        im = Image.open(catalog / "AppIcon.appiconset" / img["filename"])
        check(im.size == (1024, 1024), "AppIcon 1024 is not 1024x1024")

# ---------------------------------------------------------------- 4. Swift structure
def strip_strings_comments(src):
    # Strings first (URLs contain //, which a naive comment stripper
    # would eat), then block comments, then line comments.
    src = re.sub(r'"""(?:\\.|[^"\\])*?"""', '""""""', src, flags=re.DOTALL)
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.DOTALL)
    src = re.sub(r'//.*', '', src)
    return src

for f in swift_files:
    src = f.read_text()
    clean = strip_strings_comments(src)
    for a, b, name in (("(", ")", "parens"), ("{", "}", "braces"), ("[", "]", "brackets")):
        check(clean.count(a) == clean.count(b),
              f"{f.name}: unbalanced {name} ({clean.count(a)} vs {clean.count(b)})")
    check("TODO" not in src and "FIXME" not in src and "placeholder" not in src.lower(),
          f"{f.name}: contains TODO/FIXME/placeholder marker")
    check("fatalError" not in src, f"{f.name}: contains fatalError")

# ---------------------------------------------------------------- 5. secrets sweep
secret_patterns = [
    r"sk-[A-Za-z0-9]{10,}", r"AKIA[0-9A-Z]{16}",
    r"AIza[0-9A-Za-z_-]{10,}", r"ghp_[A-Za-z0-9]{10,}",
    r"Basic [A-Za-z0-9+/=]{10,}", r"Bearer [A-Za-z0-9_.-]{10,}",
    r"password\s*=\s*\"[^\"]{4,}\"", r"api[_-]?key\s*=\s*\"[^\"]{4,}\"",
    r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----",
]
for f in list(swift_files) + [APP / "Info.plist", PBX]:
    src = f.read_text(errors="replace")
    for pat in secret_patterns:
        m = re.search(pat, src)
        check(not m, f"{f.name}: looks like a secret ({pat})")

# The project must not contain anything copied from Regulur's Router
# (where the hardcoded Basic Auth credential lives) or any Stripe /
# Braintree / Maps key.
for needle in ("braintree", "stripe", "googlemaps", "firebase", "FBSDK",
               "lesscut", "regulurapp", "com.lesscut"):
    check(needle.lower() not in swift_text.lower(), f"Swift contains Regulur leftover '{needle}'")

print(f"Checked {len(swift_files)} Swift files, {len(asset_names)} assets.")
if warnings:
    print("WARNINGS:")
    for w in warnings:
        print("  -", w)
if errors:
    print("ERRORS:")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("All checks pass.")
