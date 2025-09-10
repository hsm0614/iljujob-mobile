import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthInterceptor extends Interceptor {
  final Dio _dio;

  AuthInterceptor(this._dio);

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    // 토큰 만료인 경우에만 실행
    if (err.response?.statusCode == 401) {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');
      final userType = prefs.getString('userType');
      final baseUrl = 'https://albailju.co.kr'; // 수정 필요 시 여기에

      if (refreshToken == null || userType == null) {
        return handler.next(err); // 리프레시 토큰 없으면 그냥 실패 처리
      }

      try {
        final response = await _dio.post(
          '$baseUrl/api/auth/refresh-token',
          data: jsonEncode({
            'refreshToken': refreshToken,
            'userType': userType,
          }),
          options: Options(
            headers: {'Content-Type': 'application/json'},
          ),
        );

        final newAccessToken = response.data['accessToken'];
        if (newAccessToken != null) {
          // 토큰 저장
          await prefs.setString('authToken', newAccessToken);

          // 이전 요청에 새 토큰 적용해서 재시도
          final cloneRequest = await _retryRequest(err.requestOptions, newAccessToken);
          return handler.resolve(cloneRequest);
        }
      } catch (e) {
        print('❌ 토큰 갱신 실패: $e');
        return handler.next(err); // 실패하면 그냥 에러로 처리
      }
    }

    // 401 아니면 그냥 통과
    return handler.next(err);
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions requestOptions, String newToken) {
    final newOptions = Options(
      method: requestOptions.method,
      headers: Map<String, dynamic>.from(requestOptions.headers)
        ..['Authorization'] = 'Bearer $newToken',
    );

    return _dio.request(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: newOptions,
    );
  }
}
