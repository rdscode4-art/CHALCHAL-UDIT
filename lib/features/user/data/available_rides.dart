import 'package:flutter/material.dart';

/// Each ride has a [category] (used for broad grouping on the home screen)
/// and a [vehicleType] (used for exact driver matching).
///
/// vehicleType must match the 'vehicleType' field in DriverRepository exactly:
///   sedan, ev, bike, auto, suv
const List<Map<String, dynamic>> availableRides = [
  {
    'category': 'bike',
    'vehicleType': 'bike',
    'name': 'Bike',
    'icon': Icons.pedal_bike,
    'price': '₹89',
    'detail': 'Quick & affordable bike ride',
    'dropTime': 'Drop 1:24 pm',
  },
  {
    'category': 'auto',
    'vehicleType': 'auto',
    'name': 'Auto',
    'icon': Icons.electric_rickshaw,
    'price': '₹131',
    'detail': 'Fast city auto',
    'dropTime': 'Drop 1:27 pm',
  },
  {
    'category': 'ev',
    'vehicleType': 'ev',
    'name': 'EV',
    'icon': Icons.directions_car,
    'price': '₹175',
    'detail': 'Affordable AC EV',
    'dropTime': 'Drop 1:30 pm',
  },
  {
    'category': 'sedan',
    'vehicleType': 'sedan',
    'name': 'Sedan',
    'icon': Icons.local_taxi,
    'price': '₹210',
    'detail': 'Comfortable sedan ride',
    'dropTime': 'Drop 1:29 pm',
  },
  {
    'category': 'suv',
    'vehicleType': 'suv',
    'name': 'SUV',
    'icon': Icons.airport_shuttle,
    'price': '₹379',
    'detail': 'Spacious SUV for groups',
    'dropTime': 'Drop 1:36 pm',
  },
];
