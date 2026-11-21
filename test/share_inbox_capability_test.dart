import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lancloud/core/platform_capabilities.dart';
import 'package:lancloud/core/share_inbox.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  group('SharedInbox', () {
    test('Android 应该读取初始分享并转发运行中内容', () async {
      final stream = StreamController<List<SharedMediaFile>>.broadcast();
      addTearDown(stream.close);
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
            path: 'https://share.example/initial',
            type: SharedMediaType.url,
          ),
          SharedMediaFile(path: '/tmp/initial.pdf', type: SharedMediaType.file),
        ],
        mediaStream: stream.stream,
      );
      final inbox = SharedInbox(capabilities: PlatformCapabilities.android);
      addTearDown(inbox.dispose);

      await inbox.init();
      expect(inbox.pendingText, 'https://share.example/initial');
      expect(inbox.pendingFiles, ['/tmp/initial.pdf']);

      String? receivedText;
      List<String>? receivedFiles;
      inbox.onText = (text) => receivedText = text;
      inbox.onFiles = (files) => receivedFiles = files;
      inbox.attach();

      stream.add([
        SharedMediaFile(
          path: 'https://share.example/runtime',
          type: SharedMediaType.url,
        ),
        SharedMediaFile(path: '/tmp/runtime.pdf', type: SharedMediaType.file),
      ]);
      await pumpEventQueue();

      expect(receivedText, 'https://share.example/runtime');
      expect(receivedFiles, ['/tmp/runtime.pdf']);
    });

    for (final (:name, :capabilities) in [
      (name: 'Windows', capabilities: PlatformCapabilities.windows),
      (name: 'iOS', capabilities: PlatformCapabilities.ios),
    ]) {
      test('$name 应该忽略初始分享和运行中媒体流', () async {
        final stream = StreamController<List<SharedMediaFile>>.broadcast();
        addTearDown(stream.close);
        ReceiveSharingIntent.setMockValues(
          initialMedia: [
            SharedMediaFile(
              path: 'https://share.example/initial',
              type: SharedMediaType.url,
            ),
          ],
          mediaStream: stream.stream,
        );
        final inbox = SharedInbox(capabilities: capabilities);
        addTearDown(inbox.dispose);
        var callbacks = 0;
        inbox.onText = (_) => callbacks += 1;
        inbox.onFiles = (_) => callbacks += 1;

        await inbox.init();
        inbox.attach();
        stream.add([
          SharedMediaFile(
            path: 'https://share.example/runtime',
            type: SharedMediaType.url,
          ),
        ]);
        await pumpEventQueue();

        expect(inbox.pendingText, isNull);
        expect(inbox.pendingFiles, isEmpty);
        expect(callbacks, 0);
      });
    }
  });
}
