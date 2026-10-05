import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/backup/backup_recovery_service.dart';

class _ExportPanel extends FilePickerPlatform {
  _ExportPanel(this.destination);

  final Uri? destination;
  String? fileName;
  Uint8List? bytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.fileName = fileName;
    this.bytes = bytes;
    return destination;
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    fail('The export panel flow must not ask for a directory');
  }
}

void main() {
  late FilePickerPlatform original;

  setUp(() => original = FilePickerPlatform.instance);
  tearDown(() => FilePickerPlatform.instance = original);

  test('only iOS saves a backup through the export panel', () {
    expect(BackupRecoveryService.savesThroughExportPanel(TargetPlatform.iOS), isTrue);
    for (final platform in TargetPlatform.values.where((value) => value != TargetPlatform.iOS)) {
      expect(BackupRecoveryService.savesThroughExportPanel(platform), isFalse, reason: platform.name);
    }
  });

  test('the export panel receives the named backup document', () async {
    final panel = _ExportPanel(Uri.file('/private/var/mobile/Documents/purelive_2026-10-04T12_00_00.txt'));
    FilePickerPlatform.instance = panel;

    final saved = await BackupRecoveryService.exportBackupDocument(
      fileName: 'purelive_2026-10-04T12_00_00.txt',
      content: '{\n  "弹匣": ["来了"]\n}',
    );

    expect(saved, isTrue);
    expect(panel.fileName, 'purelive_2026-10-04T12_00_00.txt');
    expect(utf8.decode(panel.bytes!), '{\n  "弹匣": ["来了"]\n}');
  });

  test('dismissing the export panel is not a saved backup', () async {
    FilePickerPlatform.instance = _ExportPanel(null);

    expect(await BackupRecoveryService.exportBackupDocument(fileName: 'purelive.txt', content: '{}'), isFalse);
  });
}
