import 'package:intl/intl.dart';

/// Dinheiro anda sempre em centavos (int). Valor de cobrança em double acaba
/// gerando diferença de um centavo entre o que o app mostra e o que o terminal cobra.
final NumberFormat _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

String formatCents(int cents) => _brl.format(cents / 100);

enum PaymentMethod {
  credit('Crédito'),
  debit('Débito'),
  pix('Pix'),
  voucher('Vale-refeição');

  const PaymentMethod(this.label);

  final String label;

  bool get usesCard => this != PaymentMethod.pix;
}

class PaymentRequest {
  const PaymentRequest({
    required this.reference,
    required this.amountCents,
    required this.method,
    this.installments = 1,
  })  : assert(amountCents > 0),
        assert(installments >= 1);

  /// Identifica esta tentativa de cobrança. É por ela que o app pergunta ao
  /// terminal "o que aconteceu com aquela cobrança?" quando a resposta se perde.
  final String reference;
  final int amountCents;
  final PaymentMethod method;
  final int installments;
}

/// O desfecho de uma cobrança, do ponto de vista do terminal.
sealed class PaymentOutcome {
  const PaymentOutcome();

  Map<String, Object?> toJson();

  static PaymentOutcome fromJson(Map<String, Object?> json) => switch (json['type']) {
        'approved' => Approved(
            authCode: json['authCode']! as String,
            nsu: json['nsu']! as String,
            cardLabel: json['cardLabel'] as String?,
          ),
        'declined' => Declined(code: json['code']! as String, message: json['message']! as String),
        'aborted' => Aborted(json['reason']! as String),
        _ => Unknown(json['reason'] as String? ?? ''),
      };
}

final class Approved extends PaymentOutcome {
  const Approved({required this.authCode, required this.nsu, this.cardLabel});

  /// Código de autorização devolvido pelo emissor do cartão.
  final String authCode;

  /// Número sequencial da adquirente: é ele que identifica a venda no extrato
  /// e que o suporte da maquininha pede na hora de um estorno.
  final String nsu;

  /// "VISA •••• 4242". Nulo no Pix.
  final String? cardLabel;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'approved', 'authCode': authCode, 'nsu': nsu, 'cardLabel': cardLabel};
}

final class Declined extends PaymentOutcome {
  const Declined({required this.code, required this.message});

  final String code;
  final String message;

  @override
  Map<String, Object?> toJson() => {'type': 'declined', 'code': code, 'message': message};
}

/// Cancelada antes de processar: ninguém foi cobrado.
final class Aborted extends PaymentOutcome {
  const Aborted(this.reason);

  final String reason;

  @override
  Map<String, Object?> toJson() => {'type': 'aborted', 'reason': reason};
}

/// A resposta não chegou. O cliente PODE ter sido cobrado — só a conciliação
/// com o terminal diz. Tratar isso como "recusada" é como se cobra alguém duas vezes.
final class Unknown extends PaymentOutcome {
  const Unknown(this.reason);

  final String reason;

  @override
  Map<String, Object?> toJson() => {'type': 'unknown', 'reason': reason};
}
