#!/usr/bin/env python3
"""Generate the external-app XCTest runner in ignored build output."""
import pathlib
import sys
from xml.sax.saxutils import escape

root, app = map(pathlib.Path, sys.argv[1:])
project = app.parent / 'ScreenshotRunner.xcodeproj'
project.mkdir(parents=True, exist_ok=True)
# Stable local IDs make the generated project easy to inspect.
ids = {key: f'{index:024X}' for index, key in enumerate([
    'project', 'group', 'products', 'source', 'buildSource', 'product', 'target',
    'sources', 'frameworks', 'projectConfigList', 'targetConfigList', 'projectConfig', 'targetConfig'
], 1)}

def ref(key):
    return ids[key]

source = root / 'Tools/ScreenshotTests/ScreenshotTests.swift'
# OpenStep strings require quoting; escape paths independently of shell syntax.
def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = [
    f'{ref("project")} = {{isa = PBXProject; attributes = {{LastUpgradeCheck = 2600;}}; buildConfigurationList = {ref("projectConfigList")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; mainGroup = {ref("group")}; productRefGroup = {ref("products")}; projectDirPath = ""; targets = ({ref("target")});}};',
    f'{ref("group")} = {{isa = PBXGroup; children = ({ref("source")}, {ref("products")}); sourceTree = "<group>";}};',
    f'{ref("products")} = {{isa = PBXGroup; name = Products; children = ({ref("product")}); sourceTree = "<group>";}};',
    f'{ref("source")} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(source)}; sourceTree = "<absolute>";}};',
    f'{ref("buildSource")} = {{isa = PBXBuildFile; fileRef = {ref("source")};}};',
    f'{ref("product")} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = Screenshots.xctest; sourceTree = BUILT_PRODUCTS_DIR;}};',
    f'{ref("target")} = {{isa = PBXNativeTarget; buildConfigurationList = {ref("targetConfigList")}; buildPhases = ({ref("sources")}, {ref("frameworks")}); buildRules = (); dependencies = (); name = Screenshots; productName = Screenshots; productReference = {ref("product")}; productType = "com.apple.product-type.bundle.ui-testing";}};',
    f'{ref("sources")} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ref("buildSource")}); runOnlyForDeploymentPostprocessing = 0;}};',
    f'{ref("frameworks")} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}};',
    f'{ref("projectConfigList")} = {{isa = XCConfigurationList; buildConfigurations = ({ref("projectConfig")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;}};',
    f'{ref("targetConfigList")} = {{isa = XCConfigurationList; buildConfigurations = ({ref("targetConfig")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;}};',
    f'{ref("projectConfig")} = {{isa = XCBuildConfiguration; buildSettings = {{ALWAYS_SEARCH_USER_PATHS = NO; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0;}}; name = Debug;}};',
    f'{ref("targetConfig")} = {{isa = XCBuildConfiguration; buildSettings = {{PRODUCT_NAME = Screenshots; PRODUCT_BUNDLE_IDENTIFIER = io.github.yamakze.TiebaPureMac.ScreenshotTests; SWIFT_VERSION = 5.0; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_HARDENED_RUNTIME = NO;}}; name = Debug;}};'
]
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + '\n}; rootObject = ' + ref('project') + ';}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target")}" BuildableName="Screenshots.xctest" BlueprintName="Screenshots" ReferencedContainer="container:ScreenshotRunner.xcodeproj"/>'
(schemes / 'Screenshots.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="NO"><Testables><TestableReference skipped="NO">{buildable}</TestableReference></Testables><EnvironmentVariables>
<EnvironmentVariable key="SCREENSHOT_APP" value="{escape(str(app), {'"': '&quot;'})}" isEnabled="YES"/>
</EnvironmentVariables></TestAction></Scheme>''')
