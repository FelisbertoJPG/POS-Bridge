import 'package:flutter/material.dart';

import '../checkout/checkout_controller.dart';
import '../data/transaction_store.dart';
import '../domain/payment.dart';
import '../terminal/payment_terminal.dart';
import 'common.dart';

/// Espelha o visor da maquininha enquanto a cobrança acontece e mostra o desfecho.
class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key, required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final charging = controller.phase == ChargePhase.charging;
        return PopScope(
          // Sair da tela no meio da cobrança não para a maquininha.
          canPop: !charging,
          child: Scaffold(
            appBar: AppBar(title: const Text('Cobrança'), automaticallyImplyLeading: !charging),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: charging ? _Charging(controller) : _Result(controller),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Charging extends StatelessWidget {
  const _Charging(this.controller);

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final prompt = controller.prompt;
    final icon = switch (prompt?.kind) {
      PromptKind.insertCard => Icons.contactless,
      PromptKind.scanQr => Icons.qr_code_2,
      PromptKind.enterPin => Icons.pin,
      PromptKind.removeCard => Icons.credit_card,
      PromptKind.processing || null => Icons.sync,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatCents(controller.totalCents), style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 32),
        Icon(icon, size: 96, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          prompt?.message ?? 'Conectando à maquininha…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        const LinearProgressIndicator(),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: prompt?.canAbort ?? false ? controller.abort : null,
          child: const Text('Cancelar no terminal'),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result(this.controller);

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    final record = controller.result;
    final textTheme = Theme.of(context).textTheme;

    if (record == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 72, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(error ?? 'A cobrança não foi iniciada.', textAlign: TextAlign.center, style: textTheme.titleMedium),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar')),
        ],
      );
    }

    final look = statusLook(record.status, Theme.of(context).colorScheme);
    final (title, explanation) = switch (record.status) {
      TxStatus.approved => ('Pagamento aprovado', null),
      TxStatus.declined => ('Pagamento recusado', record.message),
      TxStatus.aborted => ('Cobrança cancelada', '${record.message ?? ''} Ninguém foi cobrado.'.trim()),
      TxStatus.refunded => ('Venda estornada', record.message),
      TxStatus.pending || TxStatus.unknown => (
          'Sem confirmação do terminal',
          '${record.message ?? ''} O cliente pode ter sido cobrado. Não cobre de novo: '
              'consulte o terminal, ele sabe o que aconteceu.'
        ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(look.icon, size: 96, color: look.color),
        const SizedBox(height: 16),
        Text(title, style: textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(formatCents(record.amountCents), style: textTheme.titleLarge),
        if (explanation != null) ...[
          const SizedBox(height: 12),
          Text(explanation, textAlign: TextAlign.center),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        _Receipt(record),
        const SizedBox(height: 24),
        if (record.status.unresolved)
          FilledButton.icon(
            onPressed: () => controller.reconcile(record),
            icon: const Icon(Icons.sync),
            label: const Text('Consultar terminal'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(record.status == TxStatus.approved ? 'Novo pedido' : 'Voltar ao carrinho'),
          ),
      ],
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt(this.record);

  final TransactionRecord record;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Forma', record.installments > 1 ? '${record.method.label} ${record.installments}x' : record.method.label),
      if (record.cardLabel != null) ('Cartão', record.cardLabel!),
      if (record.authCode != null) ('Autorização', record.authCode!),
      if (record.nsu != null) ('NSU', record.nsu!),
      ('Referência', record.reference),
      ('Horário', formatTime(record.updatedAt)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
                    SelectableText(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
