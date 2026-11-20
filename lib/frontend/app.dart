import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/i18n/strings.dart';
import '../backend/state/settings.dart';
import 'theme/theme.dart';
import 'widgets/app_shell.dart';

class VideoSplitviewApp extends ConsumerWidget {
  const VideoSplitviewApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return MaterialApp(
      title: 'Video Splitview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      locale: language.locale,
      supportedLocales: AppLanguage.values.map((language) => language.locale),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppShell(),
    );
  }
}
