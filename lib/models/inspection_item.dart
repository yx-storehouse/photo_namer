


class InspectionItem {
  final int id;
  String name;
  String type;
  String location;
  String serial;
  List<String> photoPaths; // 存储已拍照片路径
  bool isCompleted;

  InspectionItem({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.serial,
    this.photoPaths = const [],
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'location': location,
    'serial': serial,
    'photoPaths': photoPaths,
    'isCompleted': isCompleted,
  };

  factory InspectionItem.fromJson(Map<String, dynamic> json) => InspectionItem(
    id: json['id'],
    name: json['name'],
    type: json['type'],
    location: json['location'],
    serial: json['serial'],
    photoPaths: List<String>.from(json['photoPaths'] ?? []),
    isCompleted: json['isCompleted'] ?? false,
  );
}

