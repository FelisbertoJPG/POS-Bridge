import 'package:flutter/material.dart';

import 'checkout/checkout_controller.dart';
import 'data/key_value_store.dart';
import 'data/transaction_store.dart';
import 'payment/payment_service.dart';
import 'terminal/simulated_terminal.dart';
import 'ui/checkout_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = PrefsStore();

  // Trocar de maquininha é trocar esta linha por outro PaymentTerminal.
  final terminal = SimulatedTerminal(storage: storage);

  final controller = CheckoutController(
    service: PaymentService(terminal: terminal, store: TransactionStore(storage)),
    simulator: terminal,
  );
  runApp(PosBridgeApp(controller: controller));
}

class PosBridgeApp extends StatelessWidget {
  const PosBridgeApp({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorSchemeSeed: const Color(0xFFE0A030),
          brightness: brightness,
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'POS Bridge',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: CheckoutScreen(controller: controller),
    );
  }
}
