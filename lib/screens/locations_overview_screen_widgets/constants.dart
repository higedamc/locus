// Based of https://m3.material.io/components/floating-action-button/specs
import 'package:locus/constants/spacing.dart';

const FAB_SIZE = 56.0;
const FAB_MARGIN = 16.0;

const OUT_OF_BOUND_MARKER_X_PADDING = SMALL_SPACE;
const OUT_OF_BOUND_MARKER_TOP_PADDING = HUGE_SPACE + MEDIUM_SPACE;
const OUT_OF_BOUND_MARKER_SIZE = 60;
const OUT_OF_BOUND_MARKER_BOTTOM_PADDING =
    FAB_SIZE + FAB_MARGIN + OUT_OF_BOUND_MARKER_SIZE + MEDIUM_SPACE;
// 250 km
const MAX_TOTAL_DIFF_IN_METERS = 250000;
