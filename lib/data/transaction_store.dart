import 'dart:convert';

import '../domain/payment.dart';
import 'key_value_store.dart';

enum TxStatus {
  pending('Aguardando terminal'),
  approved('Aprovada'),
  declined('Recusada'),
  aborted('Cancelada'),
  unknown('Sem confirmação'),
  refunded('Estornada');

  const TxStatus(this.label);

  final String label;

  /// Status em que ainda não se sabe se o cliente foi cobrado.
  bool get unresolved => this == TxStatus.pending || this == TxStatus.unknown;
}

class TransactionRecord {
  const TransactionRecord({
    required this.reference,
    required this.amountCents,
    required this.method,
    required this.installments,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.authCode,
    this.nsu,
    this.cardLabel,
    this.message,
  });

  factory TransactionRecord.pending(PaymentRequest request, DateTime now) => TransactionRecord(
        reference: request.reference,
        amountCents: request.amountCents,
        method: request.method,
        installments: request.installments,
        status: TxStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

  factory TransactionRecord.fromJson(Map<String, Object?> json) => TransactionRecord(
        reference: json['reference']! as String,
        amountCents: json['amountCents']! as int,
        method: PaymentMethod.values.byName(json['method']! as String),
        installments: json['installments']! as int,
        status: TxStatus.values.byName(json['status']! as String),
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
        authCode: json['authCode'] as String?,
        nsu: json['nsu'] as String?,
        cardLabel: json['cardLabel'] as String?,
        message: json['message'] as String?,
      );

  final String reference;
  final int amountCents;
  final PaymentMethod method;
  final int installments;
  final TxStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? authCode;
  final String? nsu;
  final String? cardLabel;
  final String? message;

  TransactionRecord _copy({
    required TxStatus status,
    required DateTime updatedAt,
    String? authCode,
    String? nsu,
    String? cardLabel,
    String? message,
  }) =>
      TransactionRecord(
        reference: reference,
        amountCents: amountCents,
        method: method,
        installments: installments,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        authCode: authCode ?? this.authCode,
        nsu: nsu ?? this.nsu,
        cardLabel: cardLabel ?? this.cardLabel,
        message: message,
      );

  TransactionRecord withOutcome(PaymentOutcome outcome, DateTime now) => switch (outcome) {
        Approved() => _copy(
            status: TxStatus.approved,
            updatedAt: now,
            authCode: outcome.authCode,
            nsu: outcome.nsu,
            cardLabel: outcome.cardLabel,
          ),
        Declined() => _copy(
            status: TxStatus.declined,
            updatedAt: now,
            message: '${outcome.message} (código ${outcome.code})',
          ),
        Aborted() => _copy(status: TxStatus.aborted, updatedAt: now, message: outcome.reason),
        Unknown() => _copy(status: TxStatus.unknown, updatedAt: now, message: outcome.reason),
      };

  TransactionRecord asRefunded(DateTime now) =>
      _copy(status: TxStatus.refunded, updatedAt: now, message: 'Estorno confirmado pelo terminal.');

  Map<String, Object?> toJson() => {
        'reference': reference,
        'amountCents': amountCents,
        'method': method.name,
        'installments': installments,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'authCode': authCode,
        'nsu': nsu,
        'cardLabel': cardLabel,
        'message': message,
      };
}

/// Histórico local das cobranças, persistido a cada mudança de status.
class TransactionStore {
  TransactionStore(this._kv);

  static const _key = 'transactions';

  final KeyValueStore _kv;
  List<TransactionRecord>? _cache;

  Future<List<TransactionRecord>> all() async {
    final cached = _cache ??= await _load();
    final sorted = [...cached]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  Future<TransactionRecord?> find(String reference) async {
    for (final record in await all()) {
      if (record.reference == reference) return record;
    }
    return null;
  }

  Future<void> save(TransactionRecord record) async {
    final list = _cache ??= await _load();
    final index = list.indexWhere((r) => r.reference == record.reference);
    if (index >= 0) {
      list[index] = record;
    } else {
      list.add(record);
    }
    await _kv.write(_key, jsonEncode([for (final r in list) r.toJson()]));
  }

  Future<List<TransactionRecord>> _load() async {
    final raw = await _kv.read(_key);
    if (raw == null) return [];
    return [
      for (final item in jsonDecode(raw) as List) TransactionRecord.fromJson((item as Map).cast<String, Object?>()),
    ];
  }
}
