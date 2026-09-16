class CommerceProduct {
  const CommerceProduct({
    required this.id,
    required this.kind,
    required this.amount,
    this.name,
    this.passType,
    this.plan,
    this.entitlementVersion,
    this.count,
    this.instant,
    this.urgent,
    this.maxRecipients,
    this.unlimitedInstant = false,
    this.priorityCs = false,
  });

  final String id;
  final String kind;
  final int amount;
  final String? name;
  final String? passType;
  final String? plan;
  final String? entitlementVersion;
  final int? count;
  final int? instant;
  final int? urgent;
  final int? maxRecipients;
  final bool unlimitedInstant;
  final bool priorityCs;

  static CommerceProduct? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final kind = json['kind']?.toString().trim() ?? '';
    final amount = _int(json['amount']);
    if (id.isEmpty ||
        !{'pass', 'subscription'}.contains(kind) ||
        amount == null) {
      return null;
    }
    return CommerceProduct(
      id: id,
      kind: kind,
      amount: amount,
      name: json['name']?.toString(),
      passType: json['passType']?.toString(),
      plan: json['plan']?.toString(),
      entitlementVersion: json['entitlementVersion']?.toString(),
      count: _int(json['count']),
      instant: _int(json['instant']),
      urgent: _int(json['urgent']),
      maxRecipients: _int(json['maxRecipients']),
      unlimitedInstant: json['unlimitedInstant'] == true,
      priorityCs: json['priorityCs'] == true,
    );
  }

  static int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
}
