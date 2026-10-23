# POS Bridge

App de caixa em Flutter que cobra por uma maquininha de cartão, com a maquininha
atrás de uma interface. O foco não é a tela de pagamento. É o que acontece quando
a cobrança dá errado no meio do caminho.

## O problema que o projeto resolve

Integrar com maquininha parece simples: manda o valor, recebe "aprovado". O
problema é o caso em que a resposta não chega. O Bluetooth cai, o app da
adquirente trava ou o celular fecha o app, e o caixa fica sem saber se o
cliente foi cobrado.

Se o app trata isso como "recusado", o operador cobra de novo e o cliente paga
duas vezes. Se trata como "aprovado", a loja entrega sem receber. O POS Bridge
não chuta nenhum dos dois:

1. **Grava antes de cobrar.** A transação é salva como *pendente* antes de o app
   falar com o terminal. Se o app morrer no meio, sobra o registro.
2. **Timeout vira "sem confirmação", não "recusada".** O cliente pode ter pago.
3. **Bloqueia nova cobrança** enquanto existir transação sem confirmação.
4. **Concilia com o terminal.** O app pergunta ao terminal o que aconteceu com
   aquela referência. Isso acontece sozinho na próxima abertura do app ou pelo
   botão *Consultar terminal*.
5. **Estorno** só de venda aprovada, e só uma vez.

## Demonstração

O terminal padrão é um simulador com quatro cenários, que dá para trocar no topo
da tela:

| Cenário | O que mostra |
|---|---|
| Aprovar | Fluxo normal: cartão, senha, aprovação com código de autorização e NSU |
| Recusar | Recusa do emissor com código e motivo |
| Cliente desiste | Cancelamento no visor, sem cobrança |
| Resposta perdida | O terminal aprova, a resposta não volta, o app bloqueia e concilia |

Para ver a recuperação depois de uma queda, escolha *Aprovar*, comece uma cobrança
e feche o app (ou recarregue a página na web) quando o visor pedir *Retire o cartão*: nesse ponto o terminal já aprovou.
Quando o app abrir de novo, ele avisa que conciliou a cobrança.

## Arquitetura

```
lib/
  domain/payment.dart              valores em centavos, pedido, desfecho (sealed)
  terminal/payment_terminal.dart   contrato que qualquer maquininha cumpre
  terminal/simulated_terminal.dart maquininha de mentira, com "livro" persistente
  payment/payment_service.dart     regras: gravar antes, timeout, bloqueio, conciliação, estorno
  data/transaction_store.dart      histórico local das transações
  checkout/checkout_controller.dart estado das telas (ChangeNotifier)
  ui/                              carrinho, visor da cobrança, histórico
test/payment_service_test.dart     os cenários acima, sem hardware
```

O app só conhece `PaymentTerminal`. As telas e o `PaymentService` não sabem qual
maquininha está do outro lado.

### Como plugar uma maquininha de verdade

As adquirentes brasileiras (Stone, Cielo, PagBank, Getnet, Mercado Pago, entre
outras) costumam oferecer um SDK Android ou integração por deeplink/intent com o
app de pagamento delas, seja em smart POS ou num celular pareado. Os detalhes
mudam por fabricante e exigem credencial de parceiro. O caminho é sempre o mesmo:

1. Escrever um adaptador `XyzTerminal implements PaymentTerminal` em Dart.
2. Do lado Android (Kotlin), chamar o SDK ou disparar o intent e devolver o
   resultado por `MethodChannel` (resposta final) e `EventChannel` (mensagens do visor).
3. Traduzir os códigos de resposta do fabricante para `Approved`, `Declined`,
   `Aborted` ou `Unknown`.
4. Implementar `lookup` com a consulta de transação do fabricante. É o que
   viabiliza a conciliação.
5. Trocar uma linha no `main.dart`.

O `PaymentService` e as telas não mudam.

## Rodar

```bash
flutter pub get
flutter run            # Android ou Chrome
flutter test
```

## Limites

- Não há integração real com nenhuma adquirente. O simulador existe para
  demonstrar e testar o comportamento sem hardware.
- Sem impressão de comprovante nem cancelamento parcial.
- O histórico fica no aparelho (`shared_preferences`). Num produto, ele iria
  para um backend, e a conciliação também cruzaria com o extrato da adquirente.
