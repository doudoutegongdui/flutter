// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart' show ProcessException, ProcessResult;
import 'package:flutter_tools/src/ios/mac.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:mockito/mockito.dart';
import 'package:platform/platform.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import '../src/common.dart';
import '../src/context.dart';

class MockProcessManager extends Mock implements ProcessManager {}
class MockFile extends Mock implements File {}
class MockXcodeProjectInterpreter extends Mock implements XcodeProjectInterpreter {}

void main() {
  group('IMobileDevice', () {
    final FakePlatform osx = new FakePlatform.fromPlatform(const LocalPlatform())
      ..operatingSystem = 'macos';
    MockProcessManager mockProcessManager;

    setUp(() {
      mockProcessManager = new MockProcessManager();
    });

    testUsingContext('getAvailableDeviceIDs throws ToolExit when libimobiledevice is not installed', () async {
      when(mockProcessManager.run(<String>['idevice_id', '-l']))
          .thenThrow(const ProcessException('idevice_id', <String>['-l']));
      expect(() async => await iMobileDevice.getAvailableDeviceIDs(), throwsToolExit());
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('getAvailableDeviceIDs throws ToolExit when idevice_id returns non-zero', () async {
      when(mockProcessManager.run(<String>['idevice_id', '-l']))
          .thenAnswer((_) => new Future<ProcessResult>.value(new ProcessResult(1, 1, '', 'Sad today')));
      expect(() async => await iMobileDevice.getAvailableDeviceIDs(), throwsToolExit());
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('getAvailableDeviceIDs returns idevice_id output when installed', () async {
      when(mockProcessManager.run(<String>['idevice_id', '-l']))
          .thenAnswer((_) => new Future<ProcessResult>.value(new ProcessResult(1, 0, 'foo', '')));
      expect(await iMobileDevice.getAvailableDeviceIDs(), 'foo');
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    group('screenshot', () {
      final String outputPath = fs.path.join('some', 'test', 'path', 'image.png');
      MockProcessManager mockProcessManager;
      MockFile mockOutputFile;

      setUp(() {
        mockProcessManager = new MockProcessManager();
        mockOutputFile = new MockFile();
      });

      testUsingContext('error if idevicescreenshot is not installed', () async {
        when(mockOutputFile.path).thenReturn(outputPath);

        // Let `idevicescreenshot` fail with exit code 1.
        when(mockProcessManager.run(<String>['idevicescreenshot', outputPath],
            environment: null,
            workingDirectory: null
        )).thenAnswer((_) => new Future<ProcessResult>.value(new ProcessResult(4, 1, '', '')));

        expect(() async => await iMobileDevice.takeScreenshot(mockOutputFile), throwsA(anything));
      }, overrides: <Type, Generator>{
        ProcessManager: () => mockProcessManager,
        Platform: () => osx,
      });

      testUsingContext('idevicescreenshot captures and returns screenshot', () async {
        when(mockOutputFile.path).thenReturn(outputPath);
        when(mockProcessManager.run(any, environment: null, workingDirectory: null)).thenAnswer(
            (Invocation invocation) => new Future<ProcessResult>.value(new ProcessResult(4, 0, '', '')));

        await iMobileDevice.takeScreenshot(mockOutputFile);
        verify(mockProcessManager.run(<String>['idevicescreenshot', outputPath],
            environment: null,
            workingDirectory: null
        ));
      }, overrides: <Type, Generator>{
        ProcessManager: () => mockProcessManager,
      });
    });
  });

  group('Xcode', () {
    MockProcessManager mockProcessManager;
    Xcode xcode;
    MockXcodeProjectInterpreter mockXcodeProjectInterpreter;

    setUp(() {
      mockProcessManager = new MockProcessManager();
      mockXcodeProjectInterpreter = new MockXcodeProjectInterpreter();
      xcode = new Xcode();
    });

    testUsingContext('xcodeSelectPath returns null when xcode-select is not installed', () {
      when(mockProcessManager.runSync(<String>['/usr/bin/xcode-select', '--print-path']))
          .thenThrow(const ProcessException('/usr/bin/xcode-select', <String>['--print-path']));
      expect(xcode.xcodeSelectPath, isNull);
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('xcodeSelectPath returns path when xcode-select is installed', () {
      const String xcodePath = '/Applications/Xcode8.0.app/Contents/Developer';
      when(mockProcessManager.runSync(<String>['/usr/bin/xcode-select', '--print-path']))
          .thenReturn(new ProcessResult(1, 0, xcodePath, ''));
      expect(xcode.xcodeSelectPath, xcodePath);
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('xcodeVersionSatisfactory is false when version is less than minimum', () {
      when(mockXcodeProjectInterpreter.isInstalled).thenReturn(true);
      when(mockXcodeProjectInterpreter.majorVersion).thenReturn(8);
      when(mockXcodeProjectInterpreter.minorVersion).thenReturn(17);
      expect(xcode.isVersionSatisfactory, isFalse);
    }, overrides: <Type, Generator>{
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
    });

    testUsingContext('xcodeVersionSatisfactory is false when xcodebuild tools are not installed', () {
      when(mockXcodeProjectInterpreter.isInstalled).thenReturn(false);
      expect(xcode.isVersionSatisfactory, isFalse);
    }, overrides: <Type, Generator>{
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
    });

    testUsingContext('xcodeVersionSatisfactory is true when version meets minimum', () {
      when(mockXcodeProjectInterpreter.isInstalled).thenReturn(true);
      when(mockXcodeProjectInterpreter.majorVersion).thenReturn(9);
      when(mockXcodeProjectInterpreter.minorVersion).thenReturn(0);
      expect(xcode.isVersionSatisfactory, isTrue);
    }, overrides: <Type, Generator>{
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
    });

    testUsingContext('xcodeVersionSatisfactory is true when major version exceeds minimum', () {
      when(mockXcodeProjectInterpreter.isInstalled).thenReturn(true);
      when(mockXcodeProjectInterpreter.majorVersion).thenReturn(10);
      when(mockXcodeProjectInterpreter.minorVersion).thenReturn(0);
      expect(xcode.isVersionSatisfactory, isTrue);
    }, overrides: <Type, Generator>{
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
    });

    testUsingContext('xcodeVersionSatisfactory is true when minor version exceeds minimum', () {
      when(mockXcodeProjectInterpreter.isInstalled).thenReturn(true);
      when(mockXcodeProjectInterpreter.majorVersion).thenReturn(9);
      when(mockXcodeProjectInterpreter.minorVersion).thenReturn(1);
      expect(xcode.isVersionSatisfactory, isTrue);
    }, overrides: <Type, Generator>{
      XcodeProjectInterpreter: () => mockXcodeProjectInterpreter,
    });

    testUsingContext('eulaSigned is false when clang is not installed', () {
      when(mockProcessManager.runSync(<String>['/usr/bin/xcrun', 'clang']))
          .thenThrow(const ProcessException('/usr/bin/xcrun', <String>['clang']));
      expect(xcode.eulaSigned, isFalse);
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('eulaSigned is false when clang output indicates EULA not yet accepted', () {
      when(mockProcessManager.runSync(<String>['/usr/bin/xcrun', 'clang']))
          .thenReturn(new ProcessResult(1, 1, '', 'Xcode EULA has not been accepted.\nLaunch Xcode and accept the license.'));
      expect(xcode.eulaSigned, isFalse);
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });

    testUsingContext('eulaSigned is true when clang output indicates EULA has been accepted', () {
      when(mockProcessManager.runSync(<String>['/usr/bin/xcrun', 'clang']))
          .thenReturn(new ProcessResult(1, 1, '', 'clang: error: no input files'));
      expect(xcode.eulaSigned, isTrue);
    }, overrides: <Type, Generator>{
      ProcessManager: () => mockProcessManager,
    });
  });

  group('Diagnose Xcode build failure', () {
    Map<String, String> buildSettings;

    setUp(() {
      buildSettings = <String, String>{
        'PRODUCT_BUNDLE_IDENTIFIER': 'test.app',
      };
    });

    testUsingContext('No provisioning profile shows message', () async {
      final XcodeBuildResult buildResult = new XcodeBuildResult(
        success: false,
        stdout: '''
Launching lib/main.dart on iPhone in debug mode...
Signing iOS app for device deployment using developer identity: "iPhone Developer: test@flutter.io (1122334455)"
Running Xcode build...                                1.3s
Failed to build iOS app
Error output from Xcode build:
↳
    ** BUILD FAILED **


    The following build commands failed:
    	Check dependencies
    (1 failure)
Xcode's output:
↳
    Build settings from command line:
        ARCHS = arm64
        BUILD_DIR = /Users/blah/blah
        DEVELOPMENT_TEAM = AABBCCDDEE
        ONLY_ACTIVE_ARCH = YES
        SDKROOT = iphoneos10.3

    === CLEAN TARGET Runner OF PROJECT Runner WITH CONFIGURATION Release ===

    Check dependencies
    [BCEROR]No profiles for 'com.example.test' were found:  Xcode couldn't find a provisioning profile matching 'com.example.test'.
    [BCEROR]Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    [BCEROR]Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    [BCEROR]Code signing is required for product type 'Application' in SDK 'iOS 10.3'

    Create product structure
    /bin/mkdir -p /Users/blah/Runner.app

    Clean.Remove clean /Users/blah/Runner.app.dSYM
        builtin-rm -rf /Users/blah/Runner.app.dSYM

    Clean.Remove clean /Users/blah/Runner.app
        builtin-rm -rf /Users/blah/Runner.app

    Clean.Remove clean /Users/blah/Runner-dfvicjniknvzghgwsthwtgcjhtsk/Build/Intermediates/Runner.build/Release-iphoneos/Runner.build
        builtin-rm -rf /Users/blah/Runner-dfvicjniknvzghgwsthwtgcjhtsk/Build/Intermediates/Runner.build/Release-iphoneos/Runner.build

    ** CLEAN SUCCEEDED **

    === BUILD TARGET Runner OF PROJECT Runner WITH CONFIGURATION Release ===

    Check dependencies
    No profiles for 'com.example.test' were found:  Xcode couldn't find a provisioning profile matching 'com.example.test'.
    Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    Code signing is required for product type 'Application' in SDK 'iOS 10.3'

Could not build the precompiled application for the device.

Error launching application on iPhone.''',
        xcodeBuildExecution: new XcodeBuildExecution(
          buildCommands: <String>['xcrun', 'xcodebuild', 'blah'],
          appDirectory: '/blah/blah',
          buildForPhysicalDevice: true,
          buildSettings: buildSettings,
        ),
      );

      await diagnoseXcodeBuildFailure(buildResult);
      expect(
        testLogger.errorText,
        contains('No Provisioning Profile was found for your project\'s Bundle Identifier or your \ndevice.'),
      );
    });

    testUsingContext('No development team shows message', () async {
      final XcodeBuildResult buildResult = new XcodeBuildResult(
        success: false,
        stdout: '''
Running "flutter packages get" in flutter_gallery...  0.6s
Launching lib/main.dart on x in release mode...
Running pod install...                                1.2s
Running Xcode build...                                1.4s
Failed to build iOS app
Error output from Xcode build:
↳
    ** BUILD FAILED **


    The following build commands failed:
    	Check dependencies
    (1 failure)
Xcode's output:
↳
    blah

    === CLEAN TARGET url_launcher OF PROJECT Pods WITH CONFIGURATION Release ===

    Check dependencies

    blah

    === CLEAN TARGET Pods-Runner OF PROJECT Pods WITH CONFIGURATION Release ===

    Check dependencies

    blah

    === CLEAN TARGET Runner OF PROJECT Runner WITH CONFIGURATION Release ===

    Check dependencies
    [BCEROR]Signing for "Runner" requires a development team. Select a development team in the project editor.
    [BCEROR]Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    [BCEROR]Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    [BCEROR]Code signing is required for product type 'Application' in SDK 'iOS 10.3'

    blah

    ** CLEAN SUCCEEDED **

    === BUILD TARGET url_launcher OF PROJECT Pods WITH CONFIGURATION Release ===

    Check dependencies

    blah

    === BUILD TARGET Pods-Runner OF PROJECT Pods WITH CONFIGURATION Release ===

    Check dependencies

    blah

    === BUILD TARGET Runner OF PROJECT Runner WITH CONFIGURATION Release ===

    Check dependencies
    Signing for "Runner" requires a development team. Select a development team in the project editor.
    Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    Code signing is required for product type 'Application' in SDK 'iOS 10.3'
    Code signing is required for product type 'Application' in SDK 'iOS 10.3'

Could not build the precompiled application for the device.''',
        xcodeBuildExecution: new XcodeBuildExecution(
          buildCommands: <String>['xcrun', 'xcodebuild', 'blah'],
          appDirectory: '/blah/blah',
          buildForPhysicalDevice: true,
          buildSettings: buildSettings,
        ),
      );

      await diagnoseXcodeBuildFailure(buildResult);
      expect(
        testLogger.errorText,
        contains('Building a deployable iOS app requires a selected Development Team with a \nProvisioning Profile.'),
      );
    });
  });
}
