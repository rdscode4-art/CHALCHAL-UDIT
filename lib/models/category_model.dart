/// Single ride category (Bike, Auto, Sedan, etc.) returned by
/// GET /api/user/categories  or  GET /api/driver/categories
class CategoryModel {
  final String id;
  final String name;

  /// Lowercase key used for matching — e.g. "bike", "auto", "sedan"
  final String key;

  final String description;

  /// Relative path from the server, e.g. "/uploads/categories/category-xxx.png"
  final String imageUrl;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.key,
    required this.description,
    required this.imageUrl,
  });

  /// Full image URL to use directly in Image.network()
  String fullImageUrl(String baseUrl) {
    if (imageUrl.isEmpty) return '';
    if (imageUrl.startsWith('http')) return imageUrl;
    return '$baseUrl$imageUrl';
  }

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      key: (json['key'] ?? json['name'] ?? '').toString().toLowerCase().trim(),
      description: (json['description'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? json['image'] ?? json['icon'] ?? '')
          .toString(),
    );
  }

  @override
  String toString() => 'CategoryModel(key: $key, name: $name)';
}
