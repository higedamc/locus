import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/svg.dart';
import 'package:locus/constants/spacing.dart';
import 'package:locus/init_quick_actions.dart';
import 'package:locus/screens/welcome_screen_widgets/BatteryOptimizationsScreen.dart';
import 'package:locus/screens/welcome_screen_widgets/PermissionsScreen.dart';
import 'package:locus/screens/welcome_screen_widgets/SimpleContinuePage.dart';
import 'package:lottie/lottie.dart';

import '../utils/theme.dart';
import 'MainScreen.dart';

const storage = FlutterSecureStorage();

enum Page {
  welcome,
  explanation,
  locationPermission,
  batteryOptimizations,
  done,
}

class WelcomeScreen extends StatefulWidget {
  final bool hasLocationAlwaysGranted;
  final bool isIgnoringBatteryOptimizations;

  const WelcomeScreen({
    required this.hasLocationAlwaysGranted,
    required this.isIgnoringBatteryOptimizations,
    Key? key,
  }) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _controller = PageController();

  @override
  void initState() {
    super.initState();

    // Reset
    actions.clearShortcutItems();
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  void _nextScreen(final int page) {
    _controller.animateToPage(page,
        duration: 500.ms, curve: Curves.easeOutExpo);
  }

  void _onDone() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const MainScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shades = getPrimaryColorShades(context);
    final l10n = AppLocalizations.of(context);

    return PlatformScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MEDIUM_SPACE),
          child: PageView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              SimpleContinuePage(
                title: l10n.welcomeScreen_title,
                description: l10n.welcomeScreen_description,
                continueLabel: l10n.welcomeScreen_getStarted,
                header: SvgPicture.asset(
                  "assets/logo.svg",
                  width: 150,
                  height: 150,
                ).animate().scale(
                      begin: const Offset(0, 0),
                      end: const Offset(1, 1),
                      duration: FADE_IN_DURATION,
                    ),
                onContinue: () {
                  _nextScreen(Page.explanation.index);
                },
              ),
              SimpleContinuePage(
                title: l10n.welcomeScreen_explanation_title,
                description: l10n.welcomeScreen_explanation_description,
                continueLabel: l10n.welcomeScreen_explanation_understood,
                header: Lottie.asset(
                  "assets/lotties/lock.json",
                  delegates: LottieDelegates(
                    values: [
                      // wave
                      ValueDelegate.strokeColor(
                        const ["Formebene 1", "Ellipse 1", "Kontur 1"],
                        value: shades[0],
                      ),
                      // Lock
                      ValueDelegate.color(
                        const ["unlock Konturen", "Gruppe 1", "Fläche 1"],
                        value: shades[0],
                      ),
                      // Background
                      ValueDelegate.color(
                        const ["unlock Konturen", "Kreis", "Fläche 1"],
                        value:
                            getIsDarkMode(context) ? shades[900] : shades[200],
                      ),
                    ],
                  ),
                ),
                onContinue: () {
                  if (Platform.isAndroid) {
                    if (widget.hasLocationAlwaysGranted) {
                      _nextScreen(Page.batteryOptimizations.index);
                    } else {
                      _nextScreen(Page.locationPermission.index);
                    }
                  } else {
                    if (widget.hasLocationAlwaysGranted) {
                      _onDone();
                    } else {
                      _nextScreen(Page.locationPermission.index);
                    }
                  }
                },
              ),
              PermissionsScreen(
                onGranted: () {
                  if (Platform.isAndroid) {
                    if (widget.isIgnoringBatteryOptimizations) {
                      _onDone();
                    } else {
                      _nextScreen(Page.batteryOptimizations.index);
                    }
                  } else {
                    _onDone();
                  }
                },
              ),
              BatteryOptimizationsScreen(onDone: _onDone),
            ],
          ),
        ),
      ),
    );
  }
}
