import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/transaction_store.dart';
import '../domain/payment.dart';
import '../payment/payment_service.dart';
import '../terminal/payment_terminal.dart';
import '../terminal/simulated_terminal.dart';

class Product {
  const Product(this.name, this.priceCents);

  final String name;
  final int priceCents;
}

const catalog = [
  Product('Espresso', 750),
  Product('Cappuccino', 1290),
  Product('Pão de queijo', 600),
  Product('Croissant', 1150),
  Product('Bolo de cenoura', 900),
  Product('Água com gás', 450),
];

enum ChargePhase { idle, charging, finished }

/// Estado das telas: carrinho, cobrança em andamento e histórico.
class CheckoutController extends ChangeNotifier {
  CheckoutController({required this.service, this.simulator});

  final PaymentService service;

  /// Presente só quando o terminal é o simulador, para trocar o cenário pela tela.
  final SimulatedTerminal? simulator;

  final Map<Product, int> _cart = {};
  final Random _random = Random();

  List<TransactionRecord> history = [];
  ChargePhase phase = ChargePhase.idle;
  TerminalPrompt? prompt;
  TransactionRecord? result;
  String? error;

  int quantityOf(Product product) => _cart[product] ?? 0;

  int get totalCents => _cart.entries.fold(0, (sum, e) => sum + e.key.priceCents * e.value);

  /// Parcela mínima de R$ 5,00, no máximo 6x.
  int get maxInstallments => (totalCents ~/ 500).clamp(1, 6);

  bool get hasUnresolved => history.any((t) => t.status.unresolved);

  void add(Product product) {
    _cart[product] = quantityOf(product) + 1;
    notifyListeners();
  }

  void remove(Product product) {
    final quantity = quantityOf(product) - 1;
    if (quantity <= 0) {
      _cart.remove(product);
    } else {
      _cart[product] = quantity;
    }
    notifyListeners();
  }

  /// Chamado ao abrir o app: resolve o que ficou pendente da última sessão.
  Future<int> start() async {
    var resolved = 0;
    try {
      resolved = await service.reconcileUnresolved();
    } finally {
      await _reloadHistory();
    }
    return resolved;
  }

  Future<void> pay(PaymentMethod method, {int installments = 1}) async {
    phase = ChargePhase.charging;
    prompt = null;
    result = null;
    error = null;
    notifyListeners();
    try {
      result = await service.charge(
        PaymentRequest(
          reference: _newReference(),
          amountCents: totalCents,
          method: method,
          installments: method == PaymentMethod.credit ? installments : 1,
        ),
        onPrompt: (p) {
          prompt = p;
          notifyListeners();
        },
      );
      if (result!.status == TxStatus.approved) _cart.clear();
    } on PaymentBlocked catch (e) {
      error = e.message;
    } finally {
      phase = ChargePhase.finished;
      await _reloadHistory();
    }
  }

  Future<void> abort() => service.terminal.abort();

  Future<void> reconcile(TransactionRecord record) async {
    try {
      final updated = await service.reconcile(record);
      if (result?.reference == updated.reference) {
        result = updated;
        if (updated.status == TxStatus.approved) _cart.clear();
      }
    } on Exception catch (e) {
      error = e.toString();
    }
    await _reloadHistory();
  }

  Future<int> reconcileAll() async {
    final resolved = await service.reconcileUnresolved();
    await _reloadHistory();
    return resolved;
  }

  /// Devolve a mensagem de erro, ou `null` se o estorno deu certo.
  Future<String?> refund(TransactionRecord record) async {
    try {
      await service.refund(record);
      return null;
    } on Exception catch (e) {
      return e.toString();
    } finally {
      await _reloadHistory();
    }
  }

  void finishPayment() {
    phase = ChargePhase.idle;
    prompt = null;
    result = null;
    error = null;
    notifyListeners();
  }

  void setScenario(Scenario scenario) {
    simulator?.scenario = scenario;
    notifyListeners();
  }

  Future<void> _reloadHistory() async {
    history = await service.history();
    notifyListeners();
  }

  String _newReference() {
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'TX-$stamp-${_random.nextInt(1296).toRadixString(36).padLeft(2, '0').toUpperCase()}';
  }
}
