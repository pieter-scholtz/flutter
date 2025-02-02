// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import '../../artifacts.dart';
import '../../base/file_system.dart';
import '../../build_info.dart';
import '../../devfs.dart';
import '../../project.dart';
import '../build_system.dart';
import '../depfile.dart';
import '../exceptions.dart';
import 'assets.dart';
import 'common.dart';
import 'desktop.dart';
import 'icon_tree_shaker.dart';

/// The only files/subdirectories we care out.
const List<String> _kLinuxArtifacts = <String>[
  'libflutter_linux_gtk.so',
];

const String _kLinuxDepfile = 'linux_engine_sources.d';

/// Copies the Linux desktop embedding files to the copy directory.
class UnpackLinux extends Target {
  const UnpackLinux(this.targetPlatform);

  final TargetPlatform targetPlatform;

  @override
  String get name => 'unpack_linux';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/linux.dart'),
  ];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<String> get depfiles => const <String>[_kLinuxDepfile];

  @override
  List<Target> get dependencies => <Target>[];

  @override
  Future<void> build(Environment environment) async {
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final String engineSourcePath = environment.artifacts
      .getArtifactPath(
        Artifact.linuxDesktopPath,
        mode: buildMode,
        platform: targetPlatform,
      );
    final String headersPath = environment.artifacts
      .getArtifactPath(
        Artifact.linuxHeaders,
        mode: buildMode,
        platform: targetPlatform,
      );
    final Directory outputDirectory = environment.fileSystem.directory(
      environment.fileSystem.path.join(
      environment.projectDir.path,
      'linux',
      'flutter',
      'ephemeral',
    ));
    final Depfile depfile = unpackDesktopArtifacts(
      fileSystem: environment.fileSystem,
      engineSourcePath: engineSourcePath,
      outputDirectory: outputDirectory,
      artifacts: _kLinuxArtifacts,
      clientSourcePaths: <String>[headersPath],
      icuDataPath: environment.artifacts.getArtifactPath(
        Artifact.icuData,
        platform: targetPlatform,
      )
    );
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      depfile,
      environment.buildDir.childFile(_kLinuxDepfile),
    );
  }
}

/// Creates a bundle for the Linux desktop target.
abstract class BundleCustomDevicesAssets extends Target {
  const BundleCustomDevicesAssets(this.targetPlatform);

  final TargetPlatform targetPlatform;

  @override
  List<Target> get dependencies => <Target>[
    const KernelSnapshot(),
    UnpackLinux(targetPlatform),
  ];

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{FLUTTER_ROOT}/packages/flutter_tools/lib/src/build_system/targets/linux.dart'),
    Source.pattern('{PROJECT_DIR}/pubspec.yaml'),
    ...IconTreeShaker.inputs,
  ];

  @override
  List<String> get depfiles => const <String>[
    'flutter_assets.d',
  ];

  @override
  Future<void> build(Environment environment) async {
    if (environment.defines[kBuildMode] == null) {
      throw MissingDefineException(kBuildMode, 'bundle_linux_assets');
    }
    final BuildMode buildMode = getBuildModeForName(environment.defines[kBuildMode]);
    final Directory outputDirectory = environment.outputDir
      .childDirectory('flutter_assets');
    if (!outputDirectory.existsSync()) {
      outputDirectory.createSync();
    }

    // Only copy the kernel blob in debug mode.
    if (buildMode == BuildMode.debug) {
      environment.buildDir.childFile('app.dill')
        .copySync(outputDirectory.childFile('kernel_blob.bin').path);
    }
    final String versionInfo = FlutterProject.current().getVersionInfo();
    final Depfile depfile = await copyAssets(
      environment,
      outputDirectory,
      targetPlatform: targetPlatform,
      additionalContent: <String, DevFSContent>{
        'version.json': DevFSStringContent(versionInfo),
      }
    );
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );
    depfileService.writeToFile(
      depfile,
      environment.buildDir.childFile('flutter_assets.d'),
    );
  }
}

/// A wrapper for AOT compilation that copies app.so into the output directory.
class CustomDevicesAotBundle extends Target {
  /// Create a [LinuxAotBundle] wrapper for [aotTarget].
  const CustomDevicesAotBundle(this.aotTarget);

  /// The [AotElfBase] subclass that produces the app.so.
  final AotElfBase aotTarget;

  @override
  String get name => 'linux_aot_bundle';

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{BUILD_DIR}/app.so'),
  ];

  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{OUTPUT_DIR}/app.so'),
  ];

  @override
  List<Target> get dependencies => <Target>[
    CopyFlutterBundle(),
    aotTarget,
  ];

  @override
  Future<void> build(Environment environment) async {
    final File outputFile = environment.buildDir.childFile('app.so');
    outputFile.copySync(environment.outputDir.childFile('app.so').path);
  }
}

class DebugCustomDevicesAssets extends BundleCustomDevicesAssets {
  const DebugCustomDevicesAssets(TargetPlatform targetPlatform) : super(targetPlatform);

  @override
  String get name => 'debug_bundle_${getNameForTargetPlatform(targetPlatform)}_assets';

  @override
  List<Source> get inputs => <Source>[
    const Source.pattern('{BUILD_DIR}/app.dill'),
  ];

  @override
  List<Source> get outputs => <Source>[
    const Source.pattern('{OUTPUT_DIR}/flutter_assets/kernel_blob.bin'),
  ];
}

class ProfileCustomDevicesAssets extends BundleCustomDevicesAssets {
  const ProfileCustomDevicesAssets(TargetPlatform targetPlatform) : super(targetPlatform);

  @override
  String get name => 'profile_bundle_${getNameForTargetPlatform(targetPlatform)}_assets';

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<Target> get dependencies => <Target>[
    ...super.dependencies,
    CustomDevicesAotBundle(AotElfProfile(targetPlatform)),
  ];
}

class ReleaseCustomDevicesAssets extends BundleCustomDevicesAssets {
  const ReleaseCustomDevicesAssets(TargetPlatform targetPlatform) : super(targetPlatform);

  @override
  String get name => 'release_bundle_${getNameForTargetPlatform(targetPlatform)}_assets';

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<Target> get dependencies => <Target>[
    ...super.dependencies,
    CustomDevicesAotBundle(AotElfRelease(targetPlatform)),
  ];
}
