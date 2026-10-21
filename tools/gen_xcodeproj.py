#!/usr/bin/env python3
"""生成 LiftNote.xcodeproj（App + 锁屏/灵动岛小组件 + 单元测试）。

新增或删除 .swift 文件后在仓库根目录运行：
    python3 tools/gen_xcodeproj.py
"""
import hashlib
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ = ROOT / "LiftNote.xcodeproj"

BUNDLE_PREFIX = "com.liftnote.journal"
DEPLOYMENT_TARGET = "17.0"


def uid(name: str) -> str:
    return hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()


def q(value) -> str:
    s = str(value)
    if s and re.fullmatch(r"[A-Za-z0-9_./$]+", s) and not s.startswith("$("):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt(value, indent: int) -> str:
    pad = "\t" * indent
    if isinstance(value, dict):
        inner = "".join(f"{pad}\t{q(k)} = {fmt(v, indent + 1)};\n" for k, v in value.items())
        return "{\n" + inner + pad + "}"
    if isinstance(value, list):
        inner = "".join(f"{pad}\t{fmt(v, indent + 1)},\n" for v in value)
        return "(\n" + inner + pad + ")"
    return q(value)


def swift_files(rel_dir: str):
    d = ROOT / rel_dir
    return sorted(p.name for p in d.glob("*.swift"))


objects = {}


def add(oid, obj):
    objects[oid] = obj
    return oid


PROJECT_ID = uid("project")
MAIN_GROUP = uid("group.main")
PRODUCTS_GROUP = uid("group.products")

# ---------- 文件 ----------
groups_spec = {
    "LiftNote": {
        "path": "LiftNote",
        "children": {
            "Core": swift_files("LiftNote/Core"),
            "App": swift_files("LiftNote/App"),
            "Views": swift_files("LiftNote/Views"),
            "Shared": swift_files("LiftNote/Shared"),
        },
        "files": ["Assets.xcassets", "Info.plist"],
    },
    "LiftNoteWidgets": {
        "path": "LiftNoteWidgets",
        "children": {},
        "files": swift_files("LiftNoteWidgets") + ["Info.plist"],
    },
    "LiftNoteTests": {
        "path": "Tests/LiftNoteCoreTests",
        "children": {},
        "files": swift_files("Tests/LiftNoteCoreTests"),
    },
}


def file_type(name):
    if name.endswith(".swift"):
        return "sourcecode.swift"
    if name.endswith(".xcassets"):
        return "folder.assetcatalog"
    if name.endswith(".plist"):
        return "text.plist.xml"
    return "text"


file_refs = {}  # 相对仓库路径 -> id
top_groups = []
for gname, spec in groups_spec.items():
    gid = uid("group." + spec["path"])
    children = []
    for sub, files in spec["children"].items():
        sid = uid("group." + spec["path"] + "/" + sub)
        sub_children = []
        for f in files:
            rel = f"{spec['path']}/{sub}/{f}"
            fid = add(uid("file." + rel), {"isa": "PBXFileReference", "lastKnownFileType": file_type(f), "path": f, "sourceTree": "<group>"})
            file_refs[rel] = fid
            sub_children.append(fid)
        add(sid, {"isa": "PBXGroup", "children": sub_children, "path": sub, "sourceTree": "<group>"})
        children.append(sid)
    for f in spec["files"]:
        rel = f"{spec['path']}/{f}"
        fid = add(uid("file." + rel), {"isa": "PBXFileReference", "lastKnownFileType": file_type(f), "path": f, "sourceTree": "<group>"})
        file_refs[rel] = fid
        children.append(fid)
    group = {"isa": "PBXGroup", "children": children, "path": spec["path"], "sourceTree": "<group>"}
    if gname != spec["path"]:
        group["name"] = gname
    add(gid, group)
    top_groups.append(gid)

APP_PRODUCT = add(uid("product.app"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": 0, "path": "LiftNote.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
WIDGET_PRODUCT = add(uid("product.widget"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.app-extension", "includeInIndex": 0, "path": "LiftNoteWidgetsExtension.appex", "sourceTree": "BUILT_PRODUCTS_DIR"})
TEST_PRODUCT = add(uid("product.tests"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle", "includeInIndex": 0, "path": "LiftNoteTests.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"})
add(PRODUCTS_GROUP, {"isa": "PBXGroup", "children": [APP_PRODUCT, WIDGET_PRODUCT, TEST_PRODUCT], "name": "Products", "sourceTree": "<group>"})
add(MAIN_GROUP, {"isa": "PBXGroup", "children": top_groups + [PRODUCTS_GROUP], "sourceTree": "<group>"})


def build_files(target, rels):
    ids = []
    for rel in rels:
        bid = add(uid(f"build.{target}.{rel}"), {"isa": "PBXBuildFile", "fileRef": file_refs[rel]})
        ids.append(bid)
    return ids


def phase(kind, target, files, **extra):
    obj = {"isa": kind, "buildActionMask": 2147483647, "files": files, "runOnlyForDeploymentPostprocessing": 0}
    obj.update(extra)
    return add(uid(f"phase.{target}.{kind}"), obj)


app_sources = [r for r in file_refs if r.startswith("LiftNote/") and r.endswith(".swift")]
widget_sources = [r for r in file_refs if r.startswith("LiftNoteWidgets/") and r.endswith(".swift")] + ["LiftNote/Shared/RestActivityAttributes.swift"]
test_sources = [r for r in file_refs if r.startswith("Tests/") and r.endswith(".swift")]

APP_TARGET = uid("target.app")
WIDGET_TARGET = uid("target.widget")
TEST_TARGET = uid("target.tests")


def config_list(name, debug, release):
    d = add(uid(f"config.{name}.debug"), {"isa": "XCBuildConfiguration", "buildSettings": debug, "name": "Debug"})
    r = add(uid(f"config.{name}.release"), {"isa": "XCBuildConfiguration", "buildSettings": release, "name": "Release"})
    return add(uid(f"configlist.{name}"), {"isa": "XCConfigurationList", "buildConfigurations": [d, r], "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})


def dependency(name, target_id, remote_name):
    proxy = add(uid(f"proxy.{name}"), {"isa": "PBXContainerItemProxy", "containerPortal": PROJECT_ID, "proxyType": 1, "remoteGlobalIDString": target_id, "remoteInfo": remote_name})
    return add(uid(f"dep.{name}"), {"isa": "PBXTargetDependency", "target": target_id, "targetProxy": proxy})


common_target = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
}

app_settings = dict(common_target, **{
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "LiftNote/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "练记",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "$(LIFTNOTE_BUNDLE_ID)",
})

widget_settings = dict(common_target, **{
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "LiftNoteWidgets/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "练记计时",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "$(LIFTNOTE_BUNDLE_ID).widgets",
    "SKIP_INSTALL": "YES",
})

test_settings = dict(common_target, **{
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": "$(LIFTNOTE_BUNDLE_ID).tests",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/LiftNote.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LiftNote",
})

project_common = {
    "LIFTNOTE_BUNDLE_ID": BUNDLE_PREFIX,
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})

# ---------- 小组件 target ----------
widget_phases = [
    phase("PBXSourcesBuildPhase", "widget", build_files("widget", widget_sources)),
    phase("PBXFrameworksBuildPhase", "widget", []),
    phase("PBXResourcesBuildPhase", "widget", []),
]
add(WIDGET_TARGET, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": config_list("widget", widget_settings, widget_settings),
    "buildPhases": widget_phases,
    "buildRules": [],
    "dependencies": [],
    "name": "LiftNoteWidgetsExtension",
    "productName": "LiftNoteWidgetsExtension",
    "productReference": WIDGET_PRODUCT,
    "productType": "com.apple.product-type.app-extension",
})

# ---------- App target ----------
embed_file = add(uid("build.app.embed.widget"), {"isa": "PBXBuildFile", "fileRef": WIDGET_PRODUCT, "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
app_phases = [
    phase("PBXSourcesBuildPhase", "app", build_files("app", app_sources)),
    phase("PBXFrameworksBuildPhase", "app", []),
    phase("PBXResourcesBuildPhase", "app", build_files("app", ["LiftNote/Assets.xcassets"])),
    phase("PBXCopyFilesBuildPhase", "app", [embed_file], dstPath="", dstSubfolderSpec=13, name="Embed Foundation Extensions"),
]
add(APP_TARGET, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": config_list("app", app_settings, app_settings),
    "buildPhases": app_phases,
    "buildRules": [],
    "dependencies": [dependency("app-widget", WIDGET_TARGET, "LiftNoteWidgetsExtension")],
    "name": "LiftNote",
    "productName": "LiftNote",
    "productReference": APP_PRODUCT,
    "productType": "com.apple.product-type.application",
})

# ---------- 测试 target ----------
test_phases = [
    phase("PBXSourcesBuildPhase", "tests", build_files("tests", test_sources)),
    phase("PBXFrameworksBuildPhase", "tests", []),
    phase("PBXResourcesBuildPhase", "tests", []),
]
add(TEST_TARGET, {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": config_list("tests", test_settings, test_settings),
    "buildPhases": test_phases,
    "buildRules": [],
    "dependencies": [dependency("tests-app", APP_TARGET, "LiftNote")],
    "name": "LiftNoteTests",
    "productName": "LiftNoteTests",
    "productReference": TEST_PRODUCT,
    "productType": "com.apple.product-type.bundle.unit-test",
})

add(PROJECT_ID, {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": 1,
        "LastSwiftUpdateCheck": 1600,
        "LastUpgradeCheck": 1600,
        "TargetAttributes": {
            APP_TARGET: {"CreatedOnToolsVersion": "16.0"},
            WIDGET_TARGET: {"CreatedOnToolsVersion": "16.0"},
            TEST_TARGET: {"CreatedOnToolsVersion": "16.0", "TestTargetID": APP_TARGET},
        },
    },
    "buildConfigurationList": config_list("project", project_debug, project_release),
    "compatibilityVersion": "Xcode 14.0",
    "developmentRegion": "zh-Hans",
    "hasScannedForEncodings": 0,
    "knownRegions": ["zh-Hans", "en", "Base"],
    "mainGroup": MAIN_GROUP,
    "productRefGroup": PRODUCTS_GROUP,
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [APP_TARGET, WIDGET_TARGET, TEST_TARGET],
})

# ---------- 输出 ----------
by_isa = {}
for oid, obj in objects.items():
    by_isa.setdefault(obj["isa"], []).append((oid, obj))

lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
for isa in sorted(by_isa):
    lines.append(f"/* Begin {isa} section */")
    for oid, obj in sorted(by_isa[isa]):
        lines.append(f"\t\t{oid} = {fmt(obj, 2)};")
    lines.append(f"/* End {isa} section */")
    lines.append("")
lines += ["\t};", f"\trootObject = {PROJECT_ID};", "}", ""]

PROJ.mkdir(exist_ok=True)
(PROJ / "project.pbxproj").write_text("\n".join(lines), encoding="utf-8")

ws = PROJ / "project.xcworkspace"
ws.mkdir(exist_ok=True)
(ws / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n',
    encoding="utf-8")

schemes = PROJ / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)


def ref(target_id, product, name):
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" '
            f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:LiftNote.xcodeproj"></BuildableReference>')


app_ref = ref(APP_TARGET, "LiftNote.app", "LiftNote")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            {ref(TEST_TARGET, "LiftNoteTests.xctest", "LiftNoteTests")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
(schemes / "LiftNote.xcscheme").write_text(scheme, encoding="utf-8")
print(f"wrote {PROJ}  ({len(app_sources)} app files, {len(widget_sources)} widget files, {len(test_sources)} test files)")
