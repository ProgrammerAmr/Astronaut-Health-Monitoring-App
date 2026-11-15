import 'package:flutter/material.dart';

import 'constants/app_colors.dart';
import 'core/state/session_controller.dart';
import 'routes/app_routes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OrbitCareApp());
}

class OrbitCareApp extends StatefulWidget {
  final SessionController? sessionController;
  final String initialRoute;

  const OrbitCareApp({
    super.key,
    this.sessionController,
    this.initialRoute = AppRoutes.splash,
  });

  @override
  State<OrbitCareApp> createState() => _OrbitCareAppState();
}

class _OrbitCareAppState extends State<OrbitCareApp> {
  late final SessionController _sessionController;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.sessionController != null) {
      _sessionController = widget.sessionController!;
      _ownsController = false;
    } else {
      _sessionController = SessionController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _sessionController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      controller: _sessionController,
      child: MaterialApp(
        title: 'OrbitCare',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            primary: AppColors.primary,
            surface: AppColors.background,
          ),
          fontFamily: 'Roboto',
        ),
        initialRoute: widget.initialRoute,
        onGenerateInitialRoutes: (String initialRouteName) {
          final builder = AppRoutes.routes[initialRouteName] ??
              AppRoutes.routes[AppRoutes.splash]!;
          return <Route<dynamic>>[
            MaterialPageRoute<void>(
              builder: builder,
              settings: RouteSettings(name: initialRouteName),
            ),
          ];
        },
        routes: AppRoutes.routes,
      ),
    );
  }
}
