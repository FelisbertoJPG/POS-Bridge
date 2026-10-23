import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../domain/payment.dart';
import 'common.dart';
import 'history_screen.dart';
import 'payment_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.controller});

  final CheckoutController controller;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _reconcileOnStart();
  }

  Future<void> _reconcileOnStart() async {
    final resolved = await controller.start();
    if (!mounted || resolved == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(resolved == 1
          ? 'Uma cobrança da sessão anterior foi conciliada com o terminal.'
          : '$resolved cobranças da sessão anterior foram conciliadas com o terminal.'),
    ));
  }

  Future<void> _charge() async {
    final choice = await showModalBottomSheet<(PaymentMethod, int)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MethodSheet(totalCents: controller.totalCents, maxInstallments: controller.maxInstallments),
    );
    if (choice == null || !mounted) return;
    final (method, installments) = choice;
    controller.pay(method, installments: installments);
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PaymentScreen(controller: controller)));
    controller.finishPayment();
  }

  void _openHistory() =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => HistoryScreen(controller: controller)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final total = controller.totalCents;
        final scenario = controller.simulator?.scenario;
        return Scaffold(
          appBar: AppBar(
            title: const Text('POS Bridge'),
            actions: [
              if (scenario != null)
                TextButton.icon(
                  onPressed: () => showScenarioSheet(context, controller),
                  icon: const Icon(Icons.tune),
                  label: Text(scenario.label),
                ),
              IconButton(
                tooltip: 'Histórico',
                onPressed: _openHistory,
                icon: Badge(
                  isLabelVisible: controller.hasUnresolved,
                  child: const Icon(Icons.receipt_long),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (controller.hasUnresolved)
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: const Text('Há cobrança sem confirmação'),
                    subtitle: const Text('Novas cobranças ficam bloqueadas até consultar o terminal.'),
                    trailing: TextButton(onPressed: _openHistory, child: const Text('Resolver')),
                  ),
                ),
              for (final product in catalog)
                ListTile(
                  title: Text(product.name),
                  subtitle: Text(formatCents(product.priceCents)),
                  trailing: _Stepper(
                    quantity: controller.quantityOf(product),
                    onAdd: () => controller.add(product),
                    onRemove: () => controller.remove(product),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(formatCents(total), style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  FilledButton.icon(
                    onPressed: total > 0 && !controller.hasUnresolved ? _charge : null,
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Cobrar'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onAdd, required this.onRemove});

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: quantity > 0 ? onRemove : null, icon: const Icon(Icons.remove_circle_outline)),
        SizedBox(width: 24, child: Text('$quantity', textAlign: TextAlign.center)),
        IconButton(onPressed: onAdd, icon: const Icon(Icons.add_circle_outline)),
      ],
    );
  }
}

class _MethodSheet extends StatefulWidget {
  const _MethodSheet({required this.totalCents, required this.maxInstallments});

  final int totalCents;
  final int maxInstallments;

  @override
  State<_MethodSheet> createState() => _MethodSheetState();
}

class _MethodSheetState extends State<_MethodSheet> {
  PaymentMethod method = PaymentMethod.credit;
  int installments = 1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Forma de pagamento', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(label: Text(m.label), selected: m == method, onSelected: (_) => setState(() => method = m)),
              ],
            ),
            if (method == PaymentMethod.credit && widget.maxInstallments > 1) ...[
              const SizedBox(height: 16),
              Text('Parcelas', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var n = 1; n <= widget.maxInstallments; n++)
                    ChoiceChip(
                      label: Text(n == 1 ? 'À vista' : '${n}x ${formatCents(widget.totalCents ~/ n)}'),
                      selected: n == installments,
                      onSelected: (_) => setState(() => installments = n),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context, (method, method == PaymentMethod.credit ? installments : 1)),
              child: Text('Enviar ${formatCents(widget.totalCents)} para a maquininha'),
            ),
          ],
        ),
      ),
    );
  }
}
