import 'package:flutter_test/flutter_test.dart';
import 'package:pos_bridge/data/key_value_store.dart';
import 'package:pos_bridge/data/transaction_store.dart';
import 'package:pos_bridge/domain/payment.dart';
import 'package:pos_bridge/payment/payment_service.dart';
import 'package:pos_bridge/terminal/payment_terminal.dart';
import 'package:pos_bridge/terminal/simulated_terminal.dart';

void main() {
  late MemoryStore storage;
  late SimulatedTerminal terminal;
  late PaymentService service;

  PaymentService newService() => PaymentService(
        terminal: terminal,
        store: TransactionStore(storage),
        responseTimeout: const Duration(milliseconds: 100),
      );

  PaymentRequest request(String reference, {PaymentMethod method = PaymentMethod.credit}) =>
      PaymentRequest(reference: reference, amountCents: 2590, method: method);

  setUp(() {
    storage = MemoryStore();
    terminal = SimulatedTerminal(storage: storage, step: Duration.zero);
    service = newService();
  });

  test('cobrança aprovada guarda autorização e NSU e mostra o visor', () async {
    final prompts = <PromptKind>[];
    final record = await service.charge(request('A1'), onPrompt: (p) => prompts.add(p.kind));

    expect(record.status, TxStatus.approved);
    expect(record.authCode, hasLength(6));
    expect(record.nsu, hasLength(9));
    expect(prompts, [PromptKind.insertCard, PromptKind.enterPin, PromptKind.processing, PromptKind.removeCard]);
    expect((await service.history()).single.status, TxStatus.approved);
  });

  test('Pix pula cartão e senha', () async {
    final prompts = <PromptKind>[];
    final record = await service.charge(request('P1', method: PaymentMethod.pix), onPrompt: (p) => prompts.add(p.kind));

    expect(record.status, TxStatus.approved);
    expect(record.cardLabel, isNull);
    expect(prompts, [PromptKind.scanQr, PromptKind.processing]);
  });

  test('recusa traz o motivo e não bloqueia a próxima cobrança', () async {
    terminal.scenario = Scenario.decline;
    final declined = await service.charge(request('D1'));
    expect(declined.status, TxStatus.declined);
    expect(declined.message, contains('Saldo insuficiente'));

    terminal.scenario = Scenario.approve;
    expect((await service.charge(request('D2'))).status, TxStatus.approved);
  });

  test('operador cancela enquanto o terminal espera o cartão', () async {
    terminal = SimulatedTerminal(storage: storage, step: const Duration(milliseconds: 50));
    service = newService();

    final charging = service.charge(request('C1'), onPrompt: (p) {
      if (p.canAbort) terminal.abort();
    });

    final record = await charging;
    expect(record.status, TxStatus.aborted);
    expect(record.message, 'Cancelada pelo operador.');
  });

  test('resposta perdida vira "sem confirmação" e bloqueia nova cobrança', () async {
    terminal.scenario = Scenario.noResponse;
    final lost = await service.charge(request('L1'));
    expect(lost.status, TxStatus.unknown);

    terminal.scenario = Scenario.approve;
    expect(() => service.charge(request('L2')), throwsA(isA<PaymentBlocked>()));
  });

  test('conciliação descobre que a cobrança perdida foi aprovada, sem cobrar de novo', () async {
    terminal.scenario = Scenario.noResponse;
    final lost = await service.charge(request('L1'));

    final reconciled = await service.reconcile(lost);
    expect(reconciled.status, TxStatus.approved);
    expect(reconciled.nsu, isNotNull);

    final history = await service.history();
    expect(history, hasLength(1));
    expect(history.single.status, TxStatus.approved);
  });

  test('app que morreu no meio da venda: a próxima abertura concilia', () async {
    // Primeira sessão: o registro pendente foi gravado e o terminal aprovou,
    // mas o app fechou antes de receber a resposta.
    final pending = TransactionRecord.pending(request('K1'), DateTime(2026, 10, 23, 15));
    await TransactionStore(storage).save(pending);
    terminal.scenario = Scenario.noResponse;
    await terminal.charge(request('K1')).timeout(const Duration(milliseconds: 50), onTimeout: (sink) => sink.close()).drain<void>();

    // Segunda sessão: store e serviço novos, lendo o mesmo armazenamento.
    service = newService();
    expect(await service.reconcileUnresolved(), 1);
    expect((await service.history()).single.status, TxStatus.approved);
  });

  test('pendente que nunca chegou ao terminal vira cancelada', () async {
    await TransactionStore(storage).save(TransactionRecord.pending(request('N1'), DateTime(2026, 10, 23)));
    service = newService();

    await service.reconcileUnresolved();
    final record = (await service.history()).single;
    expect(record.status, TxStatus.aborted);
    expect(record.message, contains('não chegou ao terminal'));
  });

  test('referência não pode ser reaproveitada', () async {
    await service.charge(request('R1'));
    expect(() => service.charge(request('R1')), throwsA(isA<PaymentBlocked>()));
  });

  test('estorno só uma vez e só de venda aprovada', () async {
    final approved = await service.charge(request('E1'));
    final refunded = await service.refund(approved);
    expect(refunded.status, TxStatus.refunded);

    expect(() => service.refund(refunded), throwsA(isA<PaymentBlocked>()));
    expect(() => terminal.refund('E1'), throwsA(isA<TerminalException>()));
  });
}
