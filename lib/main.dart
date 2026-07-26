import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:photo_namer/app_route_observer.dart';
import 'package:photo_namer/pages/home/home_page.dart';
import 'package:photo_namer/rikka_page_transitions.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('availableCameras error: $e');
  }

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2563EB);
    return MaterialApp(
      title: 'photo_namer',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF6F8FC),
      ),
      onGenerateRoute: (settings) {
        return buildAppRoute<void>(
          page: HomePage(cameras: cameras),
          settings: settings,
        );
      },
    );
  }
}
