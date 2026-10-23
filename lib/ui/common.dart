import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../data/transaction_store.dart';
import '../terminal/simulated_terminal.dart';

String formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

({IconData icon, Color color}) statusLook(TxStatus status, ColorScheme scheme) => switch (status) {
      TxStatus.approved => (icon: Icons.check_circle, color: Colors.green.shade600),
      TxStatus.declined => (icon: Icons.cancel, color: scheme.error),
      TxStatus.aborted => (icon: Icons.block, color: scheme.outline),
      TxStatus.refunded => (icon: Icons.undo, color: scheme.outline),
      TxStatus.pending || TxStatus.unknown => (icon: Icons.help, color: Colors.orange.shade700),
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final TxStatus status;

  @override
  Widget build(BuildContext context) {
    final look = statusLook(status, Theme.of(context).colorScheme);
    return Chip(
      avatar: Icon(look.icon, color: look.color, size: 18),
      label: Text(status.label),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Seletor do cenário do simulador: é o que permite demonstrar os casos ruins.
Future<void> showScenarioSheet(BuildContext context, CheckoutController controller) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.simulator?.scenario;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Cenário do simulador'),
                subtitle: Text('Como a maquininha vai se comportar na próxima cobrança.'),
              ),
              for (final scenario in Scenario.values)
                ListTile(
                  leading: Icon(scenario == current ? Icons.radio_button_checked : Icons.radio_button_off),
                  title: Text(scenario.label),
                  subtitle: Text(scenario.description),
                  selected: scenario == current,
                  onTap: () {
                    controller.setScenario(scenario);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    ),
  );
}
