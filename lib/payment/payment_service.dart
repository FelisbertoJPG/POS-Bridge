import 'dart:async';

import '../data/transaction_store.dart';
import '../domain/payment.dart';
import '../terminal/payment_terminal.dart';

/// Lançada quando o app se recusa a iniciar uma cobrança.
class PaymentBlocked implements Exception {
  const PaymentBlocked(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Toda a conversa com a maquininha passa por aqui. As regras que evitam cobrar
/// o cliente duas vezes moram nesta classe, não nas telas.
class PaymentService {
  PaymentService({
    required this.terminal,
    required this.store,
    this.responseTimeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final PaymentTerminal terminal;
  final TransactionStore store;

  /// Silêncio máximo entre dois eventos do terminal. Na vida real fica na casa
  /// de minutos, porque o cliente pode demorar para digitar a senha.
  final Duration responseTimeout;

  final DateTime Function() _now;
  bool _busy = false;

  bool get busy => _busy;

  Future<List<TransactionRecord>> history() => store.all();

  Future<TransactionRecord> charge(
    PaymentRequest request, {
    void Function(TerminalPrompt prompt)? onPrompt,
  }) async {
    if (_busy) throw const PaymentBlocked('Já existe uma cobrança em andamento.');
    if (await store.find(request.reference) != null) {
      throw PaymentBlocked('A referência ${request.reference} já foi usada.');
    }
    final unresolved = (await store.all()).where((t) => t.status.unresolved);
    if (unresolved.isNotEmpty) {
      // Se a última cobrança ficou sem resposta, o cliente pode já ter pago.
      // Cobrar de novo antes de conciliar é o caminho clássico da cobrança em dobro.
      throw PaymentBlocked(
        'A cobrança ${unresolved.first.reference} ficou sem confirmação. '
        'Consulte o terminal antes de cobrar de novo.',
      );
    }

    _busy = true;
    var record = TransactionRecord.pending(request, _now());
    try {
      // Grava ANTES de falar com o terminal. Se o app morrer no meio da venda,
      // sobra um registro pendente e a próxima abertura descobre o que houve.
      await store.save(record);

      PaymentOutcome outcome = const Unknown('O terminal encerrou sem informar o resultado.');
      try {
        await for (final event in terminal.charge(request).timeout(responseTimeout)) {
          switch (event) {
            case TerminalPrompt():
              onPrompt?.call(event);
            case TerminalFinished():
              outcome = event.outcome;
          }
        }
      } on TimeoutException {
        outcome = const Unknown('O terminal parou de responder.');
      } on TerminalException catch (e) {
        // Na dúvida, fica sem confirmação: a conciliação decide depois. Marcar
        // como recusada aqui liberaria uma segunda cobrança talvez indevida.
        outcome = Unknown(e.message);
      }

      record = record.withOutcome(outcome, _now());
      await store.save(record);
      return record;
    } finally {
      _busy = false;
    }
  }

  /// Pergunta ao terminal o que aconteceu com uma cobrança sem confirmação.
  Future<TransactionRecord> reconcile(TransactionRecord record) async {
    if (!record.status.unresolved) return record;
    if (_busy) throw const PaymentBlocked('Espere a cobrança em andamento terminar.');

    final outcome = await terminal.lookup(record.reference);
    final TransactionRecord updated;
    if (outcome == null) {
      // Com uma adquirente real, confirme na documentação que "não encontrada"
      // é definitivo, e não só atraso na sincronização dela.
      updated = record.withOutcome(const Aborted('A cobrança não chegou ao terminal.'), _now());
    } else if (outcome is Unknown) {
      return record;
    } else {
      updated = record.withOutcome(outcome, _now());
    }
    await store.save(updated);
    return updated;
  }

  /// Concilia tudo o que ficou sem confirmação. Devolve quantas foram resolvidas.
  Future<int> reconcileUnresolved() async {
    var resolved = 0;
    for (final record in await store.all()) {
      if (!record.status.unresolved) continue;
      try {
        final updated = await reconcile(record);
        if (!updated.status.unresolved) resolved++;
      } on TerminalException {
        // Terminal fora do ar: a cobrança continua pendente e bloqueando novas.
      }
    }
    return resolved;
  }

  Future<TransactionRecord> refund(TransactionRecord record) async {
    if (record.status != TxStatus.approved) {
      throw PaymentBlocked('Só dá para estornar venda aprovada (esta está ${record.status.label.toLowerCase()}).');
    }
    await terminal.refund(record.reference);
    final updated = record.asRefunded(_now());
    await store.save(updated);
    return updated;
  }
}
