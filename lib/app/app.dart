import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'router.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PrivTalk',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,

      routerConfig: AppRouter.router,
    );
  }
}
