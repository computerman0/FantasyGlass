#!/usr/bin/env python3
"""Generate a deterministic, dependency-free Xcode project. No XcodeGen installation needed."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
objects = {}

class Ref(str):
    pass

def uid(name):
    return Ref(hashlib.sha256(name.encode()).hexdigest()[:24].upper())

def add(identity, **fields):
    ident = uid(identity)
    objects[ident] = fields
    return ident

def file(path, kind=None):
    types = {'.swift':'sourcecode.swift','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.xcconfig':'text.xcconfig','.xcprivacy':'text.xml','.xcassets':'folder.assetcatalog'}
    return add('file:'+path,isa='PBXFileReference',lastKnownFileType=kind or types.get(Path(path).suffix,'text'),path=path,sourceTree='<group>')

def build(path, target):
    return add('build:'+target+':'+path,isa='PBXBuildFile',fileRef=file(path))

def phase(target, kind, files):
    return add(target+kind,isa=kind,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)

base = file('Config/Base.xcconfig')
config_names = ['Debug','Release','PushDebug','PushRelease']

def configuration_list(name, settings_for):
    refs = []
    for configuration in config_names:
        refs.append(add(name+':config:'+configuration,isa='XCBuildConfiguration',baseConfigurationReference=base,buildSettings=settings_for(configuration),name=configuration))
    return add(name+':configs',isa='XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')

def common(configuration):
    debug = configuration.endswith('Debug')
    return {'SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1','SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'26.0',
            'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if debug else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if debug else 'dwarf-with-dsym',
            'ENABLE_TESTABILITY':'YES' if debug else 'NO','ONLY_ACTIVE_ARCH':'YES' if debug else 'NO',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':('DEBUG ' if debug else '')+('PUSH_ENABLED' if configuration.startswith('Push') else ''),
            'APS_ENVIRONMENT':'development' if debug else 'production','SWIFT_EMIT_LOC_STRINGS':'YES','ENABLE_PREVIEWS':'YES','PRODUCT_NAME':'$(TARGET_NAME)',
            'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}

def app_settings(configuration):
    return {**common(configuration),'PRODUCT_BUNDLE_IDENTIFIER':'$(FANTASYGLASS_BUNDLE_ID)','INFOPLIST_FILE':'Config/App-Info.plist','GENERATE_INFOPLIST_FILE':'NO',
            'CODE_SIGN_ENTITLEMENTS':'Config/Push.entitlements' if configuration.startswith('Push') else 'Config/Local.entitlements',
            'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO'}

def widget_settings(configuration):
    return {**common(configuration),'PRODUCT_BUNDLE_IDENTIFIER':'$(FANTASYGLASS_BUNDLE_ID).widgets','INFOPLIST_FILE':'Config/Widget-Info.plist','GENERATE_INFOPLIST_FILE':'NO',
            'CODE_SIGN_ENTITLEMENTS':'Config/Widget.entitlements','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES',
            'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks']}

def test_settings(configuration):
    return {**common(configuration),'PRODUCT_BUNDLE_IDENTIFIER':'$(FANTASYGLASS_BUNDLE_ID).tests','GENERATE_INFOPLIST_FILE':'YES','BUNDLE_LOADER':'$(TEST_HOST)',
            'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/FantasyGlass.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/FantasyGlass','SKIP_INSTALL':'YES'}

app_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'App').rglob('*.swift'))
shared_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Shared').rglob('*.swift'))
widget_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Widget').rglob('*.swift'))
test_files = sorted(str(p.relative_to(ROOT)) for p in (ROOT/'AppTests').rglob('*.swift'))
package = add('CorePackage',isa='XCLocalSwiftPackageReference',relativePath='Core')
app_core = add('app:core',isa='XCSwiftPackageProductDependency',package=package,productName='FantasyCore')
test_core = add('test:core',isa='XCSwiftPackageProductDependency',package=package,productName='FantasyCore')
app_core_build = add('app:core:build',isa='PBXBuildFile',productRef=app_core)
test_core_build = add('test:core:build',isa='PBXBuildFile',productRef=test_core)
app_product = add('app:product',isa='PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='FantasyGlass.app',sourceTree='BUILT_PRODUCTS_DIR')
widget_product = add('widget:product',isa='PBXFileReference',explicitFileType='wrapper.app-extension',includeInIndex=0,path='FantasyGlassWidgets.appex',sourceTree='BUILT_PRODUCTS_DIR')
test_product = add('test:product',isa='PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='FantasyGlassTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
embed_file = add('embed:widget',isa='PBXBuildFile',fileRef=widget_product,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
embed = add('embed:phase',isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[embed_file],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0)

def dependency(name, target):
    proxy = add(name+':proxy',isa='PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=uid(target),remoteInfo=target)
    return add(name+':dependency',isa='PBXTargetDependency',target=uid(target),targetProxy=proxy)

add('FantasyGlassWidgets',isa='PBXNativeTarget',buildConfigurationList=configuration_list('widget',widget_settings),
    buildPhases=[phase('widget','PBXSourcesBuildPhase',[build(p,'widget') for p in widget_files+shared_files]),phase('widget','PBXFrameworksBuildPhase',[]),phase('widget','PBXResourcesBuildPhase',[])],
    buildRules=[],dependencies=[],name='FantasyGlassWidgets',productName='FantasyGlassWidgets',productReference=widget_product,productType='com.apple.product-type.app-extension')
add('FantasyGlass',isa='PBXNativeTarget',buildConfigurationList=configuration_list('app',app_settings),
    buildPhases=[phase('app','PBXSourcesBuildPhase',[build(p,'app') for p in app_files+shared_files]),phase('app','PBXFrameworksBuildPhase',[app_core_build]),
                 phase('app','PBXResourcesBuildPhase',[build('App/Assets.xcassets','app'),build('App/PrivacyInfo.xcprivacy','app')]),embed],
    buildRules=[],dependencies=[dependency('app:widget','FantasyGlassWidgets')],name='FantasyGlass',productName='FantasyGlass',productReference=app_product,
    productType='com.apple.product-type.application',packageProductDependencies=[app_core])
add('FantasyGlassTests',isa='PBXNativeTarget',buildConfigurationList=configuration_list('tests',test_settings),
    buildPhases=[phase('tests','PBXSourcesBuildPhase',[build(p,'tests') for p in test_files]),phase('tests','PBXFrameworksBuildPhase',[test_core_build]),phase('tests','PBXResourcesBuildPhase',[])],
    buildRules=[],dependencies=[dependency('tests:app','FantasyGlass')],name='FantasyGlassTests',productName='FantasyGlassTests',productReference=test_product,
    productType='com.apple.product-type.bundle.unit-test',packageProductDependencies=[test_core])

groups = []
for name, paths in [('App',app_files+['App/Assets.xcassets','App/PrivacyInfo.xcprivacy']),('Shared',shared_files),('Widget',widget_files),('AppTests',test_files),
                    ('Config',sorted(str(p.relative_to(ROOT)) for p in (ROOT/'Config').iterdir() if p.is_file() and p.name != 'Signing.xcconfig'))]:
    groups.append(add('group:'+name,isa='PBXGroup',children=[file(p) for p in paths],name=name,sourceTree='<group>'))
products = add('Products',isa='PBXGroup',children=[app_product,widget_product,test_product],name='Products',sourceTree='<group>')
main_group = add('main',isa='PBXGroup',children=groups+[file('Core','folder'),file('README.md'),products],sourceTree='<group>')
add('project',isa='PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastSwiftUpdateCheck':'2600','LastUpgradeCheck':'2600',
    'TargetAttributes':{uid('FantasyGlass'):{'CreatedOnToolsVersion':'26.0'},uid('FantasyGlassWidgets'):{'CreatedOnToolsVersion':'26.0'},uid('FantasyGlassTests'):{'CreatedOnToolsVersion':'26.0','TestTargetID':uid('FantasyGlass')}}},
    buildConfigurationList=configuration_list('project',lambda c:{'CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','GCC_WARN_UNUSED_VARIABLE':'YES'}),compatibilityVersion='Xcode 14.0',
    developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=products,projectDirPath='',projectRoot='',
    targets=[uid('FantasyGlass'),uid('FantasyGlassWidgets'),uid('FantasyGlassTests')],packageReferences=[package])

def serialize(value, indent=0):
    pad = '\t'*indent
    if isinstance(value,Ref): return str(value)
    if isinstance(value,int): return str(value)
    if isinstance(value,str): return json.dumps(value,ensure_ascii=False)
    if isinstance(value,list): return '(\n'+''.join('\t'*(indent+1)+serialize(v,indent+1)+',\n' for v in value)+pad+')'
    if isinstance(value,dict): return '{\n'+''.join('\t'*(indent+1)+(str(k) if isinstance(k,Ref) else json.dumps(k))+ ' = '+serialize(v,indent+1)+';\n' for k,v in value.items())+pad+'}'
    raise TypeError(value)

project = {'archiveVersion':1,'classes':{},'objectVersion':56,'objects':dict(sorted(objects.items())),'rootObject':uid('project')}
project_path = ROOT/'FantasyGlass.xcodeproj'
project_path.mkdir(exist_ok=True)
(project_path/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize(project)+'\n')

def buildable(parent,target,product):
    ET.SubElement(parent,'BuildableReference',{'BuildableIdentifier':'primary','BlueprintIdentifier':str(uid(target)),'BuildableName':product,'BlueprintName':target,'ReferencedContainer':'container:FantasyGlass.xcodeproj'})

for name,debug,release in [('FantasyGlass','Debug','Release'),('FantasyGlass-Push','PushDebug','PushRelease')]:
    scheme = ET.Element('Scheme',{'LastUpgradeVersion':'2600','version':'1.3'})
    action = ET.SubElement(scheme,'BuildAction',{'parallelizeBuildables':'YES','buildImplicitDependencies':'YES'})
    entries = ET.SubElement(action,'BuildActionEntries')
    entry = ET.SubElement(entries,'BuildActionEntry',{k:'YES' for k in ['buildForTesting','buildForRunning','buildForProfiling','buildForArchiving','buildForAnalyzing']})
    buildable(entry,'FantasyGlass','FantasyGlass.app')
    test = ET.SubElement(scheme,'TestAction',{'buildConfiguration':debug,'selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB','selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','shouldUseLaunchSchemeArgsEnv':'YES'})
    testable = ET.SubElement(ET.SubElement(test,'Testables'),'TestableReference',{'skipped':'NO'})
    buildable(testable,'FantasyGlassTests','FantasyGlassTests.xctest')
    launch = ET.SubElement(scheme,'LaunchAction',{'buildConfiguration':debug,'selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB','selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','launchStyle':'0','useCustomWorkingDirectory':'NO','ignoresPersistentStateOnLaunch':'NO','debugDocumentVersioning':'YES','allowLocationSimulation':'YES'})
    buildable(ET.SubElement(launch,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}),'FantasyGlass','FantasyGlass.app')
    profile = ET.SubElement(scheme,'ProfileAction',{'buildConfiguration':release,'shouldUseLaunchSchemeArgsEnv':'YES','savedToolIdentifier':'','useCustomWorkingDirectory':'NO','debugDocumentVersioning':'YES'})
    buildable(ET.SubElement(profile,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}),'FantasyGlass','FantasyGlass.app')
    ET.SubElement(scheme,'AnalyzeAction',{'buildConfiguration':debug})
    ET.SubElement(scheme,'ArchiveAction',{'buildConfiguration':release,'revealArchiveInOrganizer':'YES'})
    ET.indent(scheme,space='  ')
    destination = project_path/'xcshareddata/xcschemes'/f'{name}.xcscheme'
    destination.parent.mkdir(parents=True,exist_ok=True)
    ET.ElementTree(scheme).write(destination,encoding='UTF-8',xml_declaration=True)
print(f'Generated {len(objects)} project objects, two schemes, and {len(app_files)+len(shared_files)} app Swift sources.')
