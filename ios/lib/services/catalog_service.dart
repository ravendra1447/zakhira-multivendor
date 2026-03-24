import 'package:dio/dio.dart';
import '../config.dart';


class CatalogService {
  static final Dio _dio = Dio();

  /// Create a new catalog and add products to it
  static Future<Map<String, dynamic>> createCatalog({
    required int userId,
    required List<int> productIds,
    String? catalogName,
  }) async {
    try {
      final response = await _dio.post(
        '${Config.baseNodeApiUrl}/products/create-catalog',
        data: {
          'user_id': userId.toString(),
          'product_ids': productIds,
          'catalog_name': catalogName,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      return response.data;
    } on DioException catch (e) {
      print('❌ Dio error creating catalog: ${e.message}');
      print('❌ Response data: ${e.response?.data}');
      return {
        'success': false,
        'message': e.response?.data?['message'] ?? 'Network error occurred',
        'error': e.message,
      };
    } catch (e) {
      print('❌ Error creating catalog: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred',
        'error': e.toString(),
      };
    }
  }

  /// Add products to an existing catalog
  static Future<Map<String, dynamic>> addToCatalog({
    required int userId,
    required List<int> productIds,
    required int catalogId,
  }) async {
    try {
      final response = await _dio.post(
        '${Config.baseNodeApiUrl}/products/add-to-catalog',
        data: {
          'user_id': userId.toString(),
          'product_ids': productIds,
          'catalog_id': catalogId,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      return response.data;
    } on DioException catch (e) {
      print('❌ Dio error adding to catalog: ${e.message}');
      print('❌ Response data: ${e.response?.data}');
      return {
        'success': false,
        'message': e.response?.data?['message'] ?? 'Network error occurred',
        'error': e.message,
      };
    } catch (e) {
      print('❌ Error adding to catalog: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred',
        'error': e.toString(),
      };
    }
  }

  /// Get all catalogs for a user
  static Future<Map<String, dynamic>> getCatalogs(int userId) async {
    try {
      final response = await _dio.get(
        '${Config.baseNodeApiUrl}/products/catalogs',
        queryParameters: {
          'user_id': userId.toString(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      return response.data;
    } on DioException catch (e) {
      print('❌ Dio error fetching catalogs: ${e.message}');
      print('❌ Response data: ${e.response?.data}');
      return {
        'success': false,
        'message': e.response?.data?['message'] ?? 'Network error occurred',
        'error': e.message,
      };
    } catch (e) {
      print('❌ Error fetching catalogs: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred',
        'error': e.toString(),
      };
    }
  }

  /// Get catalog details with all products
  static Future<Map<String, dynamic>> getCatalogDetails({
    required int userId,
    required int catalogId,
  }) async {
    try {
      final response = await _dio.get(
        '${Config.baseNodeApiUrl}/products/catalog/$catalogId',
        queryParameters: {
          'user_id': userId.toString(),
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      return response.data;
    } on DioException catch (e) {
      print('❌ Dio error fetching catalog details: ${e.message}');
      print('❌ Response data: ${e.response?.data}');
      return {
        'success': false,
        'message': e.response?.data?['message'] ?? 'Network error occurred',
        'error': e.message,
      };
    } catch (e) {
      print('❌ Error fetching catalog details: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred',
        'error': e.toString(),
      };
    }
  }
}
