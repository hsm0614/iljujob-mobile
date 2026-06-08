//lib/presentation/screens/post_job/post_job_controller.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:time_range_picker/time_range_picker.dart';

/// 위치 권한 및 현재 위치 받아오기
///
Future<Position?> getCurrentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }

    // 핵심: 명시적으로 AndroidSettings를 전달
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        forceLocationManager: true, // 여기선 이름이 바뀜!
      ),
    );
  } catch (e) {
    return null;
  }
}

/// 갤러리에서 이미지 선택
Future<File?> pickImageFromGallery() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery);
  return picked != null ? File(picked.path) : null;
}

String formatTime24H(TimeOfDay? time) {
  if (time == null) return '';
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// 시간 범위 선택
Future<TimeRange?> pickWorkingTime(BuildContext context) async {
  return await showTimeRangePicker(
    context: context,
    start: const TimeOfDay(hour: 9, minute: 0),
    end: const TimeOfDay(hour: 18, minute: 0),
    interval: const Duration(minutes: 30),
    padding: 30,
    strokeWidth: 12,
    handlerRadius: 12,
    strokeColor: Colors.deepOrange,
    handlerColor: Colors.orange,
    selectedColor: Colors.orangeAccent,
    backgroundWidget: Container(color: Colors.black87),
  );
}

/// 주소에서 시(city) 정보 추출
String extractCity(String fullAddress) {
  final parts = fullAddress.split(' ');
  if (parts.isNotEmpty) {
    String first = parts[0];
    if (first.contains('광역시') || first.contains('특별시')) {
      return first.replaceAll(RegExp(r'[광역시|특별시]'), '');
    } else if (first.contains('도')) {
      return parts.length > 1 ? parts[1] : first;
    } else {
      return first;
    }
  }
  return '';
}
