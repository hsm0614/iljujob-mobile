// dio_client.dart
import 'package:dio/dio.dart';
import 'auth_interceptor.dart';

final dio = Dio(BaseOptions(
  baseUrl: 'https://albailju.co.kr',
  headers: {'Content-Type': 'application/json'},
));

void initializeDio() { // ← 이 함수가 반드시 있어야 함
  dio.interceptors.add(AuthInterceptor(dio));
}
