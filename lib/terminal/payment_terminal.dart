import '../domain/payment.dart';

/// Contrato que qualquer maquininha precisa cumprir para o app.
///
/// O resto do app só conhece esta interface. Trocar Stone por Cielo, PagBank ou
/// Getnet é escrever outro adaptador, sem mexer em tela nem em regra de negócio.
abstract interface class PaymentTerminal {
  String get name;

  /// Inicia a cobrança. Emite os avisos do visor e termina com um único
  /// [TerminalFinished]. O stream também pode simplesmente parar de emitir
  /// (Bluetooth caiu, app da adquirente travou), então quem chama precisa de timeout.
  Stream<TerminalEvent> charge(PaymentRequest request);

  /// Pede para desistir da cobrança em andamento. Só vale enquanto o terminal
  /// espera o cartão; depois que ele começa a processar, o pedido é ignorado.
  Future<void> abort();

  /// Pergunta ao terminal o desfecho de uma cobrança. É a base da conciliação.
  /// `null` = a cobrança nunca chegou ao terminal.
  Future<PaymentOutcome?> lookup(String reference);

  /// Estorna uma venda aprovada. Lança [TerminalException] se o terminal recusar.
  Future<void> refund(String reference);
}

enum PromptKind { insertCard, scanQr, enterPin, processing, removeCard }

sealed class TerminalEvent {
  const TerminalEvent();
}

/// O que o visor da maquininha está pedindo ao cliente neste momento.
final class TerminalPrompt extends TerminalEvent {
  const TerminalPrompt(this.kind, this.message);

  final PromptKind kind;
  final String message;

  bool get canAbort => kind == PromptKind.insertCard || kind == PromptKind.scanQr;
}

final class TerminalFinished extends TerminalEvent {
  const TerminalFinished(this.outcome);

  final PaymentOutcome outcome;
}

class TerminalException implements Exception {
  const TerminalException(this.message);

  final String message;

  @override
  String toString() => message;
}
