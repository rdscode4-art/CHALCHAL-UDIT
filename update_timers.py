import re

def update_file(path, replacements):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    for old, new in replacements:
        content = content.replace(old, new)
        
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

# 1. driver_home_screen.dart
driver_home_replacements = [
    (
        "Timer? _dashboardSyncTimer;",
        "Timer? _dashboardSyncTimer;\n  Timer? _locationEmitTimer;"
    ),
    (
        "    _dashboardSyncTimer?.cancel();\n    _dashboardSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {\n      if (mounted) {\n        _syncDashboardData();\n        _checkActiveRide();\n      }\n    });",
        "    _dashboardSyncTimer?.cancel();\n    _dashboardSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {\n      if (mounted) {\n        _syncDashboardData();\n        _checkActiveRide();\n      }\n    });\n\n    _locationEmitTimer?.cancel();\n    _locationEmitTimer = Timer.periodic(const Duration(seconds: 5), (_) {\n      if (mounted && _isOnline && _currentLatLng != null) {\n        _updateLocationOnServer(_currentLatLng!.latitude, _currentLatLng!.longitude);\n      }\n    });"
    ),
    (
        "    _dashboardSyncTimer?.cancel();\n    WidgetsBinding.instance.removeObserver(this);",
        "    _dashboardSyncTimer?.cancel();\n    _locationEmitTimer?.cancel();\n    WidgetsBinding.instance.removeObserver(this);"
    ),
]
update_file('lib/features/driver/screens/driver_home_screen.dart', driver_home_replacements)

# 2. driver_active_ride_screen.dart
driver_active_replacements = [
    (
        "Timer? _statusPollTimer;",
        "Timer? _statusPollTimer;\n  Timer? _locationEmitTimer;"
    ),
    (
        "    _progressTimer = Timer.periodic(\n      const Duration(seconds: 5),\n      (_) => _fetchRideProgress(),\n    );",
        "    _progressTimer = Timer.periodic(\n      const Duration(seconds: 5),\n      (_) => _fetchRideProgress(),\n    );\n    _locationEmitTimer = Timer.periodic(const Duration(seconds: 5), (_) {\n      if (mounted && _driverLatLng != null) {\n        SocketService().emitLocation(\n          rideId: widget.rideId,\n          lat: _driverLatLng!.latitude,\n          lng: _driverLatLng!.longitude,\n        );\n        _updateDbLocation(_driverLatLng!.latitude, _driverLatLng!.longitude);\n      }\n    });"
    ),
    (
        "    _progressTimer?.cancel();\n    _statusPollTimer?.cancel();",
        "    _progressTimer?.cancel();\n    _statusPollTimer?.cancel();\n    _locationEmitTimer?.cancel();"
    )
]
update_file('lib/features/driver/screens/driver_active_ride_screen.dart', driver_active_replacements)

# 3. user_home_screen.dart
user_home_replacements = [
    (
        "_nearbyDriversTimer = Timer.periodic(const Duration(seconds: 10), (timer) {",
        "_nearbyDriversTimer = Timer.periodic(const Duration(seconds: 5), (timer) {"
    )
]
update_file('lib/features/user/screens/user_home_screen.dart', user_home_replacements)

# 4. user_ride_progress_screen.dart
user_progress_replacements = [
    (
        "    // Fallback: poll driver GPS from API every 8s when socket is silent\n    _driverLocationPollTimer ??= Timer.periodic(\n      const Duration(seconds: 8),\n      (_) => _refreshDriverLocationFromApi(),\n    );",
        "    // Fallback: poll driver GPS from API every 5s when socket is silent\n    _driverLocationPollTimer ??= Timer.periodic(\n      const Duration(seconds: 5),\n      (_) => _refreshDriverLocationFromApi(),\n    );"
    )
]
update_file('lib/features/user/screens/user_ride_progress_screen.dart', user_progress_replacements)

print("All timers updated to 5 seconds successfully.")
