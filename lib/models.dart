class Product {
  final String id;
  final String name;
  final String image;
  final int price;
  final String category;
  final String description;
  final bool isPopular;

  Product({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.category,
    required this.description,
    this.isPopular = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id:          json['id']          as String,
      name:        json['name']        as String,
      image:       (json['image_url']  as String?) ?? '',
      price:       json['price']       as int,
      category:    json['category']    as String,
      description: (json['description'] as String?) ?? '',
      isPopular:   (json['is_popular'] as bool?) ?? false,
    );
  }
}

class CartItem {
  final Product product;
  final String milkType;
  final String sweetness;
  int quantity;

  CartItem({
    required this.product,
    required this.milkType,
    required this.sweetness,
    this.quantity = 1,
  });

  String get uniqueId => '${product.id}_$milkType';
}

class Order {
  final String id;
  final List<CartItem> items;
  final int total;
  final DateTime timestamp;
  final String status;
  final String estimatedTime;
  final int queueNumber;

  Order({
    required this.id,
    required this.items,
    required this.total,
    required this.timestamp,
    required this.status,
    required this.estimatedTime,
    required this.queueNumber,
  });
}

class UserProfile {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String memberTier;
  final int flowPoints;
  final DateTime memberSince;

  UserProfile({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    required this.memberTier,
    required this.flowPoints,
    required this.memberSince,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id:          json['id']          as String,
      fullName:    json['full_name']   as String,
      avatarUrl:   json['avatar_url']  as String?,
      memberTier:  json['member_tier'] as String,
      flowPoints:  json['flow_points'] as int,
      memberSince: DateTime.parse(json['member_since'] as String),
    );
  }
}
