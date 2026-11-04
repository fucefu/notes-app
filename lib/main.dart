import 'package:flutter/material.dart';

import 'models/app_config.dart';
import 'pages/config_form_page.dart';
import 'pages/home_page.dart';
import 'services/config_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = ConfigStore();
  final config = await store.load();
  runApp(NotesApp(store: store, initialConfig: config));
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key, required this.store, this.initialConfig});

  final ConfigStore store;
  final AppConfig? initialConfig;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  AppConfig? _config;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  Future<void> _persist(AppConfig config) async {
    await widget.store.save(config);
    if (!mounted) return;
    setState(() => _config = config);
  }

  Future<void> _reset() async {
    await widget.store.clear();
    if (!mounted) return;
    setState(() => _config = null);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return MaterialApp(
      title: '便签',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: config == null
          ? ConfigFormPage(
              title: '欢迎使用',
              submitLabel: '保存并连接',
              onSubmit: _persist,
            )
          : HomePage(
              config: config,
              onConfigChanged: _persist,
              onReset: _reset,
            ),
    );
  }
}
