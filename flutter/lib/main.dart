import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/components.dart';
import 'app/root_page.dart';
import 'app/store.dart';
import 'app/theme.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LedgerStore.open();
  runApp(StoreScope(store: store, child: const CentwiseApp()));
}

class CentwiseApp extends StatelessWidget {
  const CentwiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Centwise',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // 设置 → 外观 → 深色模式（自动 / 始终开启 / 始终关闭）.
      themeMode: StoreScope.of(context).themeMode,
      // 设置 → 语言. Text itself goes through tr(); this switches Flutter's own strings and date pickers.
      locale: switch (L10n.current) {
        Lang.zhHans => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        Lang.zhHant => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        Lang.en => const Locale('en'),
      },
      supportedLocales: const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final overlay = AnnotatedRegion<SystemUiOverlayStyle>(
          // The header is plain canvas: dark status bar content on white, light content on black.
          value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          // "已删除账单 · 撤销" sits above every route, so it also shows over an open sheet
          // (e.g. a bill deleted from a category's list). It floats just above the bottom action bar.
          child: Stack(children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            Positioned(
              left: 18,
              right: 18,
              bottom: MediaQuery.paddingOf(context).bottom + 80,
              child: const Material(type: MaterialType.transparency, child: Center(child: UndoDeleteToast())),
            ),
          ]),
        );
        if (!Platform.isMacOS) return overlay;
        // The Mac build is a phone-layout preview: keep the content at phone width.
        final palette = Palette.of(context);
        return ColoredBox(
          color: palette.track,
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: overlay)),
        );
      },
      home: const RootPage(),
    );
  }
}
