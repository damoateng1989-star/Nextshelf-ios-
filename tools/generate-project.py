#!/usr/bin/env python3
"""Generate NextShelf.xcodeproj/project.pbxproj.

Re-runnable: scans NextShelf/ for .swift files and the asset catalog
and emits a minimal, valid Xcode project (iOS 17, Swift 5, SwiftUI).

    python3 tools/generate-project.py

UUIDs are deterministic (sha1 of a seed string) so re-runs are stable.
No DEVELOPMENT_TEAM is set — the owner picks their team in Xcode
(Signing & Capabilities) on first open; the bundle id is com.nextshelf.app.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "NextShelf"
PROJECT = ROOT / "NextShelf.xcodeproj" / "project.pbxproj"


def uid(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


# ---------------------------------------------------------------- file inventory
swift_files = sorted(APP_DIR.rglob("*.swift"))
swift_rel = [f.relative_to(ROOT).as_posix() for f in swift_files]
assert swift_files, "no Swift files found under NextShelf/"
assert (APP_DIR / "Info.plist").exists()
assert (APP_DIR / "Assets.xcassets").exists()

# Folder groups, in the order they appear in the navigator.
GROUPS = [
    ("NextShelf", None, ["NextShelfApp.swift", "Info.plist"]),
    ("Theme", "NextShelf/Theme", None),
    ("API", "NextShelf/API", None),
    ("Salvage", "NextShelf/Salvage", None),
    ("Views", "NextShelf/Views", None),
    ("Auth", "NextShelf/Views/Auth", None),
    ("Board", "NextShelf/Views/Board", None),
    ("Watchlist", "NextShelf/Views/Watchlist", None),
    ("Alerts", "NextShelf/Views/Alerts", None),
    ("Record", "NextShelf/Views/Record", None),
]

# Map each swift file to its group by directory.
def group_for(rel: str) -> str:
    parts = Path(rel).parts
    if len(parts) == 2:
        return "NextShelf"
    if parts[1] == "Theme":
        return "Theme"
    if parts[1] == "API":
        return "API"
    if parts[1] == "Salvage":
        return "Salvage"
    if parts[1] == "Views":
        if parts[2].endswith(".swift"):
            return "Views"
        return {"Auth": "Auth", "Board": "Board", "Watchlist": "Watchlist",
                "Alerts": "Alerts", "Record": "Record"}[parts[2]]
    raise ValueError(rel)


# ---------------------------------------------------------------- object ids
ids = {}
def I(seed: str) -> str:
    if seed not in ids:
        ids[seed] = uid(seed)
    return ids[seed]

file_refs = {}
for rel in swift_rel:
    file_refs[rel] = I(f"fileref:{rel}")
file_refs["NextShelf/Info.plist"] = I("fileref:NextShelf/Info.plist")
file_refs["NextShelf/Assets.xcassets"] = I("fileref:NextShelf/Assets.xcassets")
file_refs["WebKit.framework"] = I("fileref:WebKit.framework")
file_refs["NextShelf.app"] = I("fileref:NextShelf.app")

build_files = {}
for rel in swift_rel:
    build_files[rel] = I(f"buildfile:{rel}")
build_files["NextShelf/Assets.xcassets"] = I("buildfile:NextShelf/Assets.xcassets")
build_files["WebKit.framework"] = I("buildfile:WebKit.framework")

group_ids = {name: I(f"group:{name}") for name, _, _ in GROUPS}
PROJECT_ID = I("project:NextShelf")
TARGET_ID = I("target:NextShelf")
PRODUCT_GROUP_ID = I("group:Products")
SOURCES_ID = I("phase:sources")
FRAMEWORKS_ID = I("phase:frameworks")
RESOURCES_ID = I("phase:resources")
PROJ_CFG_LIST = I("cfglist:project")
TARGET_CFG_LIST = I("cfglist:target")
PROJ_DEBUG = I("cfg:project:Debug")
PROJ_RELEASE = I("cfg:project:Release")
TARGET_DEBUG = I("cfg:target:Debug")
TARGET_RELEASE = I("cfg:target:Release")

# ---------------------------------------------------------------- sections
out = []
out.append("// !$*UTF8*$!")
out.append("{")
out.append("\tarchiveVersion = 1;")
out.append("\tclasses = {")
out.append("\t};")
out.append("\tobjectVersion = 56;")
out.append("\tobjects = {")

# PBXBuildFile
out.append("/* Begin PBXBuildFile section */")
for rel in swift_rel:
    out.append(f"\t\t{build_files[rel]} /* {Path(rel).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[rel]} /* {Path(rel).name} */; }};")
out.append(f"\t\t{build_files['NextShelf/Assets.xcassets']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs['NextShelf/Assets.xcassets']} /* Assets.xcassets */; }};")
out.append(f"\t\t{build_files['WebKit.framework']} /* WebKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {file_refs['WebKit.framework']} /* WebKit.framework */; }};")
out.append("/* End PBXBuildFile section */")

# PBXFileReference
out.append("/* Begin PBXFileReference section */")
for rel in swift_rel:
    out.append(f"\t\t{file_refs[rel]} /* {Path(rel).name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {Path(rel).name}; sourceTree = \"<group>\"; }};")
out.append(f"\t\t{file_refs['NextShelf/Info.plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
out.append(f"\t\t{file_refs['NextShelf/Assets.xcassets']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
out.append(f"\t\t{file_refs['WebKit.framework']} /* WebKit.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = WebKit.framework; path = System/Library/Frameworks/WebKit.framework; sourceTree = SDKROOT; }};")
out.append(f"\t\t{file_refs['NextShelf.app']} /* NextShelf.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NextShelf.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
out.append("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
out.append("/* Begin PBXFrameworksBuildPhase section */")
out.append(f"\t\t{FRAMEWORKS_ID} /* Frameworks */ = {{")
out.append("\t\t\tisa = PBXFrameworksBuildPhase;")
out.append("\t\t\tbuildActionMask = 2147483647;")
out.append("\t\t\tfiles = (")
out.append(f"\t\t\t\t{build_files['WebKit.framework']} /* WebKit.framework in Frameworks */,")
out.append("\t\t\t);")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out.append("\t\t};")
out.append("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
out.append("/* Begin PBXGroup section */")
# root project group: NextShelf group + Products
out.append(f"\t\t{group_ids['NextShelf']} = {{")
out.append("\t\t\tisa = PBXGroup;")
out.append("\t\t\tchildren = (")
for name, _, _ in GROUPS:
    if name == "NextShelf":
        continue
    out.append(f"\t\t\t\t{group_ids[name]} /* {name} */,")
out.append(f"\t\t\t\t{PRODUCT_GROUP_ID} /* Products */,")
out.append("\t\t\t);")
out.append("\t\t\tsourceTree = \"<group>\";")
out.append("\t\t};")
# The top-level "NextShelf" group in the file tree is the app folder group:
# Xcode projects normally have the project group (root) and the app folder
# group with the same name. We model the app folder as its own group.
APP_GROUP_ID = I("group:NextShelfApp")
# children of the app folder group
app_children = []
for rel in swift_rel:
    if group_for(rel) == "NextShelf":
        app_children.append((file_refs[rel], Path(rel).name))
app_children.append((file_refs["NextShelf/Info.plist"], "Info.plist"))
app_children.append((file_refs["NextShelf/Assets.xcassets"], "Assets.xcassets"))
out.append(f"\t\t{APP_GROUP_ID} /* NextShelf */ = {{")
out.append("\t\t\tisa = PBXGroup;")
out.append("\t\t\tchildren = (")
for ref, name in app_children:
    out.append(f"\t\t\t\t{ref} /* {name} */,")
for name in ("Theme", "API", "Salvage", "Views"):
    out.append(f"\t\t\t\t{group_ids[name]} /* {name} */,")
out.append("\t\t\t);")
out.append("\t\t\tpath = NextShelf;")
out.append("\t\t\tsourceTree = \"<group>\";")
out.append("\t\t};")
# Subgroups
for name, path, _ in GROUPS:
    if name == "NextShelf":
        continue
    children = []
    if path is None:
        continue
    for rel in swift_rel:
        if group_for(rel) == name:
            children.append((file_refs[rel], Path(rel).name))
    # Views group contains the tab subgroups, not files directly.
    if name == "Views":
        for sub in ("Auth", "Board", "Watchlist", "Alerts", "Record"):
            children.append((group_ids[sub], sub))
    out.append(f"\t\t{group_ids[name]} /* {name} */ = {{")
    out.append("\t\t\tisa = PBXGroup;")
    out.append("\t\t\tchildren = (")
    for ref, cname in children:
        out.append(f"\t\t\t\t{ref} /* {cname} */,")
    out.append("\t\t\t);")
    out.append(f"\t\t\tpath = {name};")
    out.append("\t\t\tsourceTree = \"<group>\";")
    out.append("\t\t};")
# Products group
out.append(f"\t\t{PRODUCT_GROUP_ID} /* Products */ = {{")
out.append("\t\t\tisa = PBXGroup;")
out.append("\t\t\tchildren = (")
out.append(f"\t\t\t\t{file_refs['NextShelf.app']} /* NextShelf.app */,")
out.append("\t\t\t);")
out.append("\t\t\tname = Products;")
out.append("\t\t\tsourceTree = \"<group>\";")
out.append("\t\t};")
# Root group (the project itself): app folder group + Products.
ROOT_GROUP_ID = I("group:Root")
out.append(f"\t\t{ROOT_GROUP_ID} = {{")
out.append("\t\t\tisa = PBXGroup;")
out.append("\t\t\tchildren = (")
out.append(f"\t\t\t\t{APP_GROUP_ID} /* NextShelf */,")
out.append(f"\t\t\t\t{PRODUCT_GROUP_ID} /* Products */,")
out.append("\t\t\t);")
out.append("\t\t\tsourceTree = \"<group>\";")
out.append("\t\t};")
out.append("/* End PBXGroup section */")

# PBXNativeTarget
out.append("/* Begin PBXNativeTarget section */")
out.append(f"\t\t{TARGET_ID} /* NextShelf */ = {{")
out.append("\t\t\tisa = PBXNativeTarget;")
out.append(f"\t\t\tbuildConfigurationList = {TARGET_CFG_LIST} /* Build configuration list for PBXNativeTarget \"NextShelf\" */;")
out.append("\t\t\tbuildPhases = (")
out.append(f"\t\t\t\t{SOURCES_ID} /* Sources */,")
out.append(f"\t\t\t\t{FRAMEWORKS_ID} /* Frameworks */,")
out.append(f"\t\t\t\t{RESOURCES_ID} /* Resources */,")
out.append("\t\t\t);")
out.append("\t\t\tbuildRules = (")
out.append("\t\t\t);")
out.append("\t\t\tdependencies = (")
out.append("\t\t\t);")
out.append("\t\t\tname = NextShelf;")
out.append("\t\t\tpackageProductDependencies = (")
out.append("\t\t\t);")
out.append(f"\t\t\tproductName = NextShelf;")
out.append(f"\t\t\tproductReference = {file_refs['NextShelf.app']} /* NextShelf.app */;")
out.append("\t\t\tproductType = \"com.apple.product-type.application\";")
out.append("\t\t};")
out.append("/* End PBXNativeTarget section */")

# PBXProject
out.append("/* Begin PBXProject section */")
out.append(f"\t\t{PROJECT_ID} /* Project object */ = {{")
out.append("\t\t\tisa = PBXProject;")
out.append("\t\t\tattributes = {")
out.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
out.append("\t\t\t\tLastSwiftUpdateCheck = 1500;")
out.append("\t\t\t\tLastUpgradeCheck = 1600;")
out.append("\t\t\t\tTargetAttributes = {")
out.append(f"\t\t\t\t\t{TARGET_ID} = {{")
out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
out.append("\t\t\t\t\t};")
out.append("\t\t\t\t};")
out.append("\t\t\t};")
out.append(f"\t\t\tbuildConfigurationList = {PROJ_CFG_LIST} /* Build configuration list for PBXProject \"NextShelf\" */;")
out.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
out.append("\t\t\tdevelopmentRegion = en;")
out.append("\t\t\thasScannedForEncodings = 0;")
out.append("\t\t\tknownRegions = (")
out.append("\t\t\t\ten,")
out.append("\t\t\t\tBase,")
out.append("\t\t\t);")
out.append(f"\t\t\tmainGroup = {ROOT_GROUP_ID};")
out.append(f"\t\t\tproductRefGroup = {PRODUCT_GROUP_ID} /* Products */;")
out.append("\t\t\tprojectDirPath = \"\";")
out.append("\t\t\tprojectRoot = \"\";")
out.append("\t\t\ttargets = (")
out.append(f"\t\t\t\t{TARGET_ID} /* NextShelf */,")
out.append("\t\t\t);")
out.append("\t\t};")
out.append("/* End PBXProject section */")

# PBXResourcesBuildPhase
out.append("/* Begin PBXResourcesBuildPhase section */")
out.append(f"\t\t{RESOURCES_ID} /* Resources */ = {{")
out.append("\t\t\tisa = PBXResourcesBuildPhase;")
out.append("\t\t\tbuildActionMask = 2147483647;")
out.append("\t\t\tfiles = (")
out.append(f"\t\t\t\t{build_files['NextShelf/Assets.xcassets']} /* Assets.xcassets in Resources */,")
out.append("\t\t\t);")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out.append("\t\t};")
out.append("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
out.append("/* Begin PBXSourcesBuildPhase section */")
out.append(f"\t\t{SOURCES_ID} /* Sources */ = {{")
out.append("\t\t\tisa = PBXSourcesBuildPhase;")
out.append("\t\t\tbuildActionMask = 2147483647;")
out.append("\t\t\tfiles = (")
for rel in swift_rel:
    out.append(f"\t\t\t\t{build_files[rel]} /* {Path(rel).name} in Sources */,")
out.append("\t\t\t);")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out.append("\t\t};")
out.append("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
def xcbuildconfig(cid, name, settings):
    lines = [f"\t\t{cid} /* {name} */ = {{",
             "\t\t\tisa = XCBuildConfiguration;",
             "\t\t\tbuildSettings = {"]
    for k, v in settings.items():
        if isinstance(v, list):
            lines.append(f"\t\t\t\t{k} = (")
            for item in v:
                lines.append(f"\t\t\t\t\t{item},")
            lines.append("\t\t\t\t);")
        else:
            lines.append(f"\t\t\t\t{k} = {v};")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")
    return lines

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CODE_SIGN_IDENTITY": '"-"',
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "LOCALIZATION_PREFS": '""',
    "MTL_FAST_MATH": "YES",
    "SWIFT_VERSION": "5.0",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "MTL_ENABLE_DEBUG_INFO": "YES",
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
})

target_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "VERSIONING_SYSTEM": "apple-generic",   # agvtool (CI build-number bump) needs this
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "NextShelf/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.nextshelf.app",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SDKROOT": "iphoneos",
    "SWIFT_EMBED_LIBRARIES_WITH_INSTALL": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
target_debug = dict(target_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_PREPROCESSOR_DEFINITIONS": ['"DEBUG=1"', '"$(inherited)"'],
    "MTL_ENABLE_DEBUG_INFO": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
target_release = dict(target_common, **{
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    "VALIDATE_PRODUCT": "YES",
})

out.append("/* Begin XCBuildConfiguration section */")
out.extend(xcbuildconfig(PROJ_DEBUG, "Debug", project_debug))
out.extend(xcbuildconfig(PROJ_RELEASE, "Release", project_release))
out.extend(xcbuildconfig(TARGET_DEBUG, "Debug", target_debug))
out.extend(xcbuildconfig(TARGET_RELEASE, "Release", target_release))
out.append("/* End XCBuildConfiguration section */")

# XCConfigurationList
out.append("/* Begin XCConfigurationList section */")
for lid, name, cfgs in (
    (PROJ_CFG_LIST, "Build configuration list for PBXProject \"NextShelf\"", [(PROJ_DEBUG, "Debug"), (PROJ_RELEASE, "Release")]),
    (TARGET_CFG_LIST, "Build configuration list for PBXNativeTarget \"NextShelf\"", [(TARGET_DEBUG, "Debug"), (TARGET_RELEASE, "Release")]),
):
    out.append(f"\t\t{lid} /* {name} */ = {{")
    out.append("\t\t\tisa = XCConfigurationList;")
    out.append("\t\t\tbuildConfigurations = (")
    for cid, cname in cfgs:
        out.append(f"\t\t\t\t{cid} /* {cname} */,")
    out.append("\t\t\t);")
    out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    out.append("\t\t\tdefaultConfigurationName = Release;")
    out.append("\t\t};")
out.append("/* End XCConfigurationList section */")

out.append("\t};")
out.append(f"\trootObject = {PROJECT_ID} /* Project object */;")
out.append("}")

PROJECT.parent.mkdir(parents=True, exist_ok=True)
PROJECT.write_text("\n".join(out) + "\n")
print(f"Wrote {PROJECT} ({len(swift_rel)} Swift files)")
