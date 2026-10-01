import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_controller.dart';
import 'core/notifications.dart';
import 'core/transfer/transfer_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppController();
  await app.init();
  final language = app.settings.language;
  final locale = language == 'zh'
      ? const Locale('zh')
      : language == 'en'
          ? const Locale('en')
          : null;
  await NotificationService.instance.init(locale);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: TransferManager(app)),
      ],
      child: const LanCloudApp(),
    ),
  );
}
