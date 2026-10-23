import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../data/key_value_store.dart';
import '../domain/payment.dart';
import 'payment_terminal.dart';

enum Scenario {
  approve('Aprovar', 'Fluxo normal: cartão, senha, aprovada.'),
  decline('Recusar', 'O emissor nega por saldo insuficiente.'),
  customerAborts('Cliente desiste', 'O cliente cancela no visor antes de passar o cartão.'),
  noResponse('Resposta perdida', 'O terminal aprova a venda, mas a resposta nunca chega ao app.');

  const Scenario(this.label, this.description);

  final String label;
  final String description;
}

/// Maquininha de mentira, para demonstrar e testar o app sem hardware.
///
/// Guarda num "livro" persistente o desfecho de cada cobrança, como a adquirente
/// faz do lado dela. É esse livro que a conciliação consulta, e ele continua lá
/// se o app fechar no meio de uma venda, exatamente como no mundo real.
class SimulatedTerminal implements PaymentTerminal {
  SimulatedTerminal({
    required this._storage,
    this.scenario = Scenario.approve,
    this.step = const Duration(milliseconds: 1400),
    Random? random,
  }) : _random = random ?? Random();

  static const _ledgerKey = 'simulated_terminal_ledger';
  static const _card = 'VISA •••• 4242';

  final KeyValueStore _storage;
  final Random _random;

  /// Tempo de cada etapa do visor. Zero nos testes.
  final Duration step;

  Scenario scenario;

  Completer<void>? _abortSignal;
  bool _busy = false;

  @override
  String get name => 'Simulador';

  @override
  Stream<TerminalEvent> charge(PaymentRequest request) {
    if (_busy) throw const TerminalException('O terminal já está processando outra cobrança.');
    _busy = true;
    _abortSignal = Completer<void>();
    final out = StreamController<TerminalEvent>();
    _run(request, out);
    return out.stream;
  }

  Future<void> _run(PaymentRequest request, StreamController<TerminalEvent> out) async {
    var listening = true;
    out.onCancel = () => listening = false;
    void emit(TerminalEvent event) {
      if (listening) out.add(event);
    }

    final scenario = this.scenario;
    final usesCard = request.method.usesCard;
    try {
      emit(usesCard
          ? TerminalPrompt(
              PromptKind.insertCard,
              request.method == PaymentMethod.voucher
                  ? 'Insira o cartão do vale'
                  : 'Aproxime, insira ou passe o cartão',
            )
          : const TerminalPrompt(PromptKind.scanQr, 'Leia o QR Code no visor da maquininha'));

      final abortedByOperator = await _waitOrAbort();
      if (abortedByOperator || scenario == Scenario.customerAborts) {
        final outcome = Aborted(abortedByOperator ? 'Cancelada pelo operador.' : 'O cliente cancelou no terminal.');
        await _remember(request.reference, outcome);
        emit(TerminalFinished(outcome));
        return;
      }
      _abortSignal = null;

      if (usesCard) {
        emit(const TerminalPrompt(PromptKind.enterPin, '$_card — digite a senha'));
        await Future<void>.delayed(step);
      }
      emit(const TerminalPrompt(PromptKind.processing, 'Processando…'));
      await Future<void>.delayed(step);

      final PaymentOutcome outcome = scenario == Scenario.decline
          ? const Declined(code: '51', message: 'Saldo insuficiente')
          : Approved(authCode: _digits(6), nsu: _digits(9), cardLabel: usesCard ? _card : null);

      // A adquirente registra a venda antes de responder. Daqui em diante o
      // cliente já foi cobrado, chegue a resposta ao app ou não.
      await _remember(request.reference, outcome);

      if (scenario == Scenario.noResponse) {
        // O stream fica mudo, sem fechar: quem chamou só descobre pelo timeout.
        return;
      }
      if (usesCard) {
        emit(const TerminalPrompt(PromptKind.removeCard, 'Retire o cartão'));
        await Future<void>.delayed(step);
      }
      emit(TerminalFinished(outcome));
    } finally {
      _busy = false;
      _abortSignal = null;
      if (scenario != Scenario.noResponse) await out.close();
    }
  }

  /// Espera uma etapa. Devolve `true` se o operador pediu para cancelar.
  Future<bool> _waitOrAbort() async {
    final signal = _abortSignal!;
    await Future.any([Future<void>.delayed(step), signal.future]);
    return signal.isCompleted;
  }

  @override
  Future<void> abort() async {
    final signal = _abortSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  @override
  Future<PaymentOutcome?> lookup(String reference) async {
    await Future<void>.delayed(step ~/ 2);
    final entry = (await _ledger())[reference];
    if (entry == null) return null;
    return PaymentOutcome.fromJson((entry['outcome']! as Map).cast<String, Object?>());
  }

  @override
  Future<void> refund(String reference) async {
    await Future<void>.delayed(step);
    final ledger = await _ledger();
    final entry = ledger[reference];
    if (entry == null || (entry['outcome']! as Map)['type'] != 'approved') {
      throw const TerminalException('Não há venda aprovada com essa referência.');
    }
    if (entry['refunded'] == true) throw const TerminalException('Essa venda já foi estornada.');
    entry['refunded'] = true;
    await _storage.write(_ledgerKey, jsonEncode(ledger));
  }

  Future<void> _remember(String reference, PaymentOutcome outcome) async {
    final ledger = await _ledger();
    ledger[reference] = {'outcome': outcome.toJson(), 'refunded': false};
    await _storage.write(_ledgerKey, jsonEncode(ledger));
  }

  Future<Map<String, Map<String, Object?>>> _ledger() async {
    final raw = await _storage.read(_ledgerKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as Map).cast<String, Object?>()));
  }

  String _digits(int length) => List.generate(length, (_) => _random.nextInt(10)).join();
}
