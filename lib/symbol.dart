class Symbol {
  final String value;
  final String name;

  Symbol({
    required this.value,
    required this.name,
  });

  factory Symbol.fromJson(Map<String, dynamic> json) {
    return Symbol(
      value: json['symbol'] ?? '',
      name: json['name'] ?? '',
    );
  }
}
