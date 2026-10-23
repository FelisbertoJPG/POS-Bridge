import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../data/transaction_store.dart';
import '../domain/payment.dart';
import 'common.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.controller});

  final CheckoutController controller;

  Future<void> _reconcileAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final resolved = await controller.reconcileAll();
    messenger.showSnackBar(SnackBar(
      content: Text(resolved == 0 ? 'Nada pendente para conciliar.' : '$resolved cobrança(s) conciliada(s).'),
    ));
  }

  Future<void> _refund(BuildContext context, TransactionRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estornar venda?'),
        content: Text('${formatCents(record.amountCents)} no ${record.method.label.toLowerCase()}, '
            'NSU ${record.nsu}. O valor volta para o cliente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Estornar')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = await controller.refund(record);
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Estorno confirmado.')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final history = controller.history;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Histórico'),
            actions: [
              IconButton(
                tooltip: 'Conciliar pendentes',
                onPressed: controller.hasUnresolved ? () => _reconcileAll(context) : null,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          body: history.isEmpty
              ? const Center(child: Text('Nenhuma cobrança ainda.'))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = history[i];
                    final look = statusLook(t.status, Theme.of(context).colorScheme);
                    final method = t.installments > 1 ? '${t.method.label} ${t.installments}x' : t.method.label;
                    return ListTile(
                      leading: Icon(look.icon, color: look.color),
                      title: Text('${formatCents(t.amountCents)} · $method'),
                      subtitle: Text([
                        '${t.status.label} · ${formatTime(t.createdAt)} · ${t.reference}',
                        if (t.message != null) t.message!,
                      ].join('\n')),
                      isThreeLine: t.message != null,
                      trailing: switch (t.status) {
                        TxStatus.pending || TxStatus.unknown =>
                          TextButton(onPressed: () => controller.reconcile(t), child: const Text('Consultar')),
                        TxStatus.approved =>
                          TextButton(onPressed: () => _refund(context, t), child: const Text('Estornar')),
                        _ => null,
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}
