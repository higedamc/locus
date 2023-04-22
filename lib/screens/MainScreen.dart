import 'package:animations/animations.dart';
import 'package:enough_platform_widgets/enough_platform_widgets.dart';
import 'package:flutter/material.dart';
import 'package:locus/constants/spacing.dart';
import 'package:locus/screens/main_screen_widgets/task_tile.dart';
import 'package:locus/services/task_service.dart';
import 'package:locus/utils/theme.dart';
import 'package:provider/provider.dart';

import 'CreateTaskScreen.dart';

const FAB_DIMENSION = 56.0;

class MainScreen extends StatefulWidget {
  const MainScreen({
    Key? key,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final taskService = context.watch<TaskService>();

    return PlatformScaffold(
      material: (_, __) => MaterialScaffoldData(
        floatingActionButton: taskService.tasks.isEmpty
            ? null
            : OpenContainer(
                transitionDuration: const Duration(milliseconds: 500),
                transitionType: ContainerTransitionType.fade,
                openBuilder: (context, action) => const CreateTaskScreen(),
                closedBuilder: (context, action) => SizedBox(
                  height: FAB_DIMENSION,
                  width: FAB_DIMENSION,
                  child: Center(
                    child: Icon(
                      context.platformIcons.add,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
                closedElevation: 6.0,
                closedShape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(FAB_DIMENSION / 2),
                  ),
                ),
                openColor: Theme.of(context).scaffoldBackgroundColor,
                closedColor: Theme.of(context).colorScheme.primary,
              ),
      ),
      body: Center(
        child: taskService.tasks.length == 0
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    "No tasks yet",
                    style: getSubTitleTextStyle(context),
                  ),
                  const SizedBox(height: SMALL_SPACE),
                  Text(
                    "Create a task to get started",
                    style: getCaptionTextStyle(context),
                  ),
                  const SizedBox(height: MEDIUM_SPACE),
                  PlatformElevatedButton(
                    material: (_, __) => MaterialElevatedButtonData(
                      icon: Icon(context.platformIcons.add),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => CreateTaskScreen(),
                        ),
                      );
                    },
                    child: Text("Create task"),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: taskService.tasks.length,
                itemBuilder: (context, index) {
                  final task = taskService.tasks[index];

                  return TaskTile(
                    task: task,
                  );
                },
              ),
      ),
    );
  }
}
