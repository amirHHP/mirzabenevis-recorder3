#!/usr/bin/env python3
"""Generate Xcode project for Mirza Benevis menu bar app + whisper.cpp."""

from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
MACAPP_DIR = ROOT / "MacApp"
PROJECT_DIR = MACAPP_DIR / "MirzaBenevis.xcodeproj"
WHISPER_XCFRAMEWORK = ROOT / "vendor/whisper.cpp/build-apple/whisper.xcframework"

SOURCES = sorted((MACAPP_DIR / "MirzaBenevis").rglob("*.swift"))

id_counter = 0x1000
build_files = []
file_refs = []
sources_phase = []

for src in SOURCES:
    rel = src.relative_to(MACAPP_DIR)
    base = src.name
    file_id = f"A{id_counter:07X}"
    build_id = f"B{id_counter:07X}"
    id_counter += 1

    file_refs.append(
        f'\t\t{file_id} /* {base} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = "<group>"; }};'
    )
    build_files.append(
        f'\t\t{build_id} /* {base} in Sources */ = {{isa = PBXBuildFile; '
        f'fileRef = {file_id} /* {base} */; }};'
    )
    sources_phase.append(f'\t\t\t\t{build_id} /* {base} in Sources */,')

xcframework_exists = WHISPER_XCFRAMEWORK.exists()
xcframework_rel = "../../vendor/whisper.cpp/build-apple/whisper.xcframework"

framework_build = ""
framework_ref = ""
framework_link = ""
framework_embed = ""
copy_phase = ""

if xcframework_exists:
    framework_build = """
\t\tD0000001 /* whisper.xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = D0000002 /* whisper.xcframework */; };
\t\tD0000003 /* whisper.xcframework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = D0000002 /* whisper.xcframework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };"""
    framework_ref = f"""
\t\tD0000002 /* whisper.xcframework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = whisper.xcframework; path = "{xcframework_rel}"; sourceTree = "<group>"; }};"""
    framework_link = "\t\t\t\tD0000001 /* whisper.xcframework in Frameworks */,"
    framework_embed = "\t\t\t\tD0000003 /* whisper.xcframework in Embed Frameworks */,"
    copy_phase = """
/* Begin PBXCopyFilesBuildPhase section */
\t\tD0000004 /* Embed Frameworks */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 10;
\t\t\tfiles = (
\t\t\t\tD0000003 /* whisper.xcframework in Embed Frameworks */,
\t\t\t);
\t\t\tname = "Embed Frameworks";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXCopyFilesBuildPhase section */
"""
    frameworks_group = """
\t\tD0000005 /* Frameworks */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tD0000002 /* whisper.xcframework */,
\t\t\t);
\t\t\tname = Frameworks;
\t\t\tsourceTree = "<group>";
\t\t};"""
    root_children = """
\t\t\t\tC0000018 /* MirzaBenevis */,
\t\t\t\tD0000005 /* Frameworks */,
\t\t\t\tC0000017 /* Products */,"""
    build_phases = """
\t\t\tbuildPhases = (
\t\t\t\tC0000007 /* Sources */,
\t\t\t\tC0000008 /* Frameworks */,
\t\t\t\tD0000004 /* Embed Frameworks */,
\t\t\t\tC0000009 /* Resources */,
\t\t\t);"""
else:
    framework_build = ""
    framework_ref = ""
    framework_link = ""
    copy_phase = ""
    frameworks_group = ""
    root_children = """
\t\t\t\tC0000018 /* MirzaBenevis */,
\t\t\t\tC0000017 /* Products */,"""
    build_phases = """
\t\t\tbuildPhases = (
\t\t\t\tC0000007 /* Sources */,
\t\t\t\tC0000008 /* Frameworks */,
\t\t\t\tC0000009 /* Resources */,
\t\t\t);"""
    print("WARNING: whisper.xcframework not found. Run: ./scripts/build_whisper.sh")

PROJECT_DIR.mkdir(parents=True, exist_ok=True)

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}{framework_build}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\tC0000001 /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\tC0000002 /* MirzaBenevis.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = MirzaBenevis.entitlements; sourceTree = "<group>"; }};
\t\tC0000003 /* MirzaBenevis.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MirzaBenevis.app; sourceTree = BUILT_PRODUCTS_DIR; }};
{chr(10).join(file_refs)}{framework_ref}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\tC0000008 /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{framework_link}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */
{copy_phase}
/* Begin PBXGroup section */
\t\tC0000006 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = ({root_children}
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};{frameworks_group}
\t\tC0000018 /* MirzaBenevis */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tC0000001 /* Info.plist */,
\t\t\t\tC0000002 /* MirzaBenevis.entitlements */,
\t\t\t);
\t\t\tpath = MirzaBenevis;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\tC0000017 /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\tC0000003 /* MirzaBenevis.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\tC0000004 /* MirzaBenevis */ = {{
\t\t\tisa = PBXNativeTarget;{build_phases}
\t\t\tbuildConfigurationList = C0000011 /* Build configuration list for PBXNativeTarget "MirzaBenevis" */;
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = MirzaBenevis;
\t\t\tproductName = MirzaBenevis;
\t\t\tproductReference = C0000003 /* MirzaBenevis.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\tC0000005 /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t}};
\t\t\tbuildConfigurationList = C0000010 /* Build configuration list for PBXProject "MirzaBenevis" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = fa;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tfa,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = C0000006;
\t\t\tproductRefGroup = C0000017 /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\tC0000004 /* MirzaBenevis */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\tC0000009 /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\tC0000007 /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(sources_phase)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\tC0000012 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\tC0000013 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\tC0000014 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = MirzaBenevis/MirzaBenevis.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = MirzaBenevis/Info.plist;
\t\t\t\tINFOPLIST_KEY_LSUIElement = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMARKETING_VERSION = 2.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.mirzabenevis.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\tC0000015 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = MirzaBenevis/MirzaBenevis.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = MirzaBenevis/Info.plist;
\t\t\t\tINFOPLIST_KEY_LSUIElement = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMARKETING_VERSION = 2.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.mirzabenevis.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\tC0000010 /* Build configuration list for PBXProject "MirzaBenevis" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tC0000012 /* Debug */,
\t\t\t\tC0000013 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\tC0000011 /* Build configuration list for PBXNativeTarget "MirzaBenevis" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\tC0000014 /* Debug */,
\t\t\t\tC0000015 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = C0000005 /* Project object */;
}}
"""

(PROJECT_DIR / "project.pbxproj").write_text(pbxproj)
print(f"Xcode project generated at {PROJECT_DIR}")
