#!/usr/bin/env python3
"""Dependency-free structural checks; these do NOT compile Swift or replace Xcode."""
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
text = (ROOT / 'MikaConsole.xcodeproj/project.pbxproj').read_text()
# Parse the OpenStep subset used in this hand-maintained project, not just regex IDs.
tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', re.sub(r'//[^\n]*|/\*.*?\*/', '', text, flags=re.S))
position = 0

def take(expected=None):
    global position
    token = tokens[position]
    position += 1
    if expected is not None:
        assert token == expected, (expected, token)
    return token

def parse():
    token = take()
    if token == '{':
        result = {}
        while tokens[position] != '}':
            key = take(); take('=')
            assert key not in result, f'duplicate key {key}'
            result[key] = parse(); take(';')
        take('}')
        return result
    if token == '(':
        result = []
        while tokens[position] != ')':
            result.append(parse())
            if tokens[position] == ',': take(',')
            else: assert tokens[position] == ')'
        take(')')
        return result
    return token[1:-1] if token.startswith('"') else token

project = parse()
assert position == len(tokens)
objects = project['objects']
assert all(re.fullmatch(r'[A-F0-9]{24}', key) for key in objects)
for value in objects.values():
    def check_refs(item):
        if isinstance(item, dict):
            for v in item.values(): check_refs(v)
        elif isinstance(item, list):
            for v in item: check_refs(v)
        elif re.fullmatch(r'[A-F0-9]{24}', item):
            assert item in objects, f'dangling reference {item}'
    check_refs(value)
root = objects[project['rootObject']]
assert root['isa'] == 'PBXProject'
assert len(root['targets']) == 1
native_id = root['targets'][0]
native = objects[native_id]
assert native['isa'] == 'PBXNativeTarget'
assert native['productType'] == 'com.apple.product-type.application'
source_groups = [v for v in objects.values() if v.get('isa') == 'PBXGroup' and v.get('path') == 'MikaConsole']
assert len(source_groups) == 1
source_group = source_groups[0]
for ref_id in source_group['children']:
    ref_path = ROOT / 'MikaConsole' / objects[ref_id]['path']
    if objects[ref_id].get('lastKnownFileType') == 'folder.assetcatalog':
        assert ref_path.is_dir()
    else:
        assert ref_path.is_file()
sources = [objects[key] for key in native['buildPhases'] if objects[key]['isa'] == 'PBXSourcesBuildPhase']
assert len(sources) == 1
actual = []
for build_id in sources[0]['files']:
    build = objects[build_id]
    assert build['isa'] == 'PBXBuildFile'
    ref_id = build['fileRef']
    assert ref_id in source_group['children']
    actual.append(objects[ref_id]['path'])
expected = sorted(p.name for p in (ROOT / 'MikaConsole').glob('*.swift'))
assert sorted(actual) == expected and len(actual) == len(set(actual))
for owner in (root, native):
    configs = objects[owner['buildConfigurationList']]['buildConfigurations']
    assert {objects[k]['name'] for k in configs} == {'Debug', 'Release'}
    for config_id in configs:
        settings = objects[config_id]['buildSettings']
        if owner is native:
            assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.jigaoyi.mikaconsole'
            assert settings['INFOPLIST_FILE'] == 'MikaConsole/Info.plist'
            assert settings['GENERATE_INFOPLIST_FILE'] == 'NO'
            assert settings['SUPPORTED_PLATFORMS'] == 'iphoneos iphonesimulator'
        else:
            assert settings['IPHONEOS_DEPLOYMENT_TARGET'] == '17.0'
            assert settings['SWIFT_VERSION'] == '5.0'
plist = plistlib.loads((ROOT / 'MikaConsole/Info.plist').read_bytes())
assert plist['CFBundleDisplayName'] == 'Mika 控制台'
assert plist['NSLocalNetworkUsageDescription']
assert plist['NSAppTransportSecurity'] == {'NSAllowsLocalNetworking': True}
scheme = ET.parse(ROOT / 'MikaConsole.xcodeproj/xcshareddata/xcschemes/MikaConsole.xcscheme')
for ref in scheme.iter('BuildableReference'):
    assert ref.attrib['BlueprintIdentifier'] == native_id
    assert ref.attrib['ReferencedContainer'] == 'container:MikaConsole.xcodeproj'
yaml = (ROOT / 'codemagic.yaml').read_text()
for required in ('ios-simulator-build:', 'xcodebuild build', 'generic/platform=iOS Simulator', 'CODE_SIGNING_ALLOWED=NO', 'pipefail'):
    assert required in yaml
assert 'Version 2.0, January 2004' in (ROOT / 'LICENSE').read_text()
assert 'END OF TERMS AND CONDITIONS' in (ROOT / 'LICENSE').read_text()
assert 'wangzan101/Mika' in (ROOT / 'NOTICE').read_text()
print(f'PASS: OpenStep project parsed; {len(expected)} Swift files referenced exactly once; no dangling references.')
print('PASS: target/configurations, shared scheme, Info.plist/ATS, CI build command and license checked.')
print('NOT RUN: Swift compilation, simulator launch, Keychain/ATS behavior, API integration or real-device acceptance.')
