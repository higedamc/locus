import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';

import '../utils/device.dart';

/// A widget that displays a caret icon, if required.
/// For example, on MIUI and iOS, a caret icon is displayed.
class SettingsCaretIcon extends StatelessWidget {
  const SettingsCaretIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isCupertino(context)) {
      return const Icon(CupertinoIcons.right_chevron);
    }

    if (isMIUI()) {
      return Transform.scale(
        scale: 0.9,
        child: Icon(
          CupertinoIcons.right_chevron,
          color: Theme.of(context).textTheme.bodySmall!.color,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
