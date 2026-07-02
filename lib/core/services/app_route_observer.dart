import 'package:flutter/widgets.dart';

/// Global app route observer used to detect when a route becomes visible again.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
