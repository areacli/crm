# Roteiro de homologação do adaptador Mercado Pago (boleto, Pix e cartão; incremento 20)

Roteiro **manual**, para quem tem uma aplicação no painel de desenvolvedores do Mercado Pago e uma conta de teste de um credor. Nenhum teste automático chama o Mercado Pago: os testes usam um cliente HTTP falso com respostas gravadas à mão a partir dos exemplos da documentação (`mercadopago.com.br/developers`, lida em 14/11/2026). Este roteiro confere, uma vez, o que a documentação não diz ou diz de dois jeitos. **Não escreva segredos neste arquivo, nem em capturas de tela, nem em logs que vão ao repositório.**

## Antes de começar

1. **Aplicação da instalação** no painel do Mercado Pago, com OAuth (`redirect_uri` fixo `https://<endereço público>/configuracao/integracoes/conexao/retorno`, escopo `offline_access`) e **Webhooks** configurados para o endereço `https://<endereço público>/webhooks/pagamentos/fornecedores/mercadopago`, evento de pedidos (`order`), com o segredo gerado no painel. Guarde `client_id`, `client_secret` e o segredo do webhook nas credenciais cifradas do Rails (`payments.connect.mercadopago.sandbox` e `.production`, campos `client_id`, `client_secret`, `webhook_secret`) ou nas variáveis `CRM_CONNECT_MERCADOPAGO_<AMBIENTE>_<CAMPO>`.
2. **`CRM_PUBLIC_URL`** com o endereço público em HTTPS.
3. Cadastre a integração (fornecedor Mercado Pago), clique **Conectar ao Mercado Pago**, autorize com a conta de teste e volte: a integração mostra "Conectada" com o número da conta.

## Conexão e avisos

| # | O que conferir | Por que (documentação) | Resultado |
|---|---|---|---|
| C1 | A troca do código devolve `access_token`, `refresh_token`, `expires_in`, `user_id` e `public_key` | campos da resposta não lidos (lacuna 10) | |
| C2 | A renovação devolve um `refresh_token` novo, e o antigo deixa de valer | contradição "reuso do refresh_token" | |
| C3 | Com `test_token: true`, a credencial gerada funciona na API Orders | contradição "credencial de teste na Orders" | |
| C4 | **O aviso de um pedido da conta conectada chega ao webhook da aplicação**, com `user_id` da conta | lacuna 11 (decisiva para MPG3) | |
| C5 | A assinatura `x-signature` confere com o manifesto `id:…;request-id:…;ts:…;` e o `data.id` da consulta | notificações | |
| C6 | Lista de `action` dos avisos de pedido (`order.processed`, `order.canceled`, `order.expired`, `order.refunded`?) | lacuna 12 | |
| C7 | Retentativas e IPs de origem dos avisos | lacuna 12 | |

## Pix

| # | O que conferir | Por que | Resultado |
|---|---|---|---|
| P1 | `expiration_time` em duração (`P2DT3H10M`) é aceito; validade de 30 minutos a 30 dias | contradição "exemplo da validade" | |
| P2 | Pix de teste (`amount = 50.00`, `first_name = APRO`) muda para `processed`; o aviso chega e o título baixa | teste de Pix | |
| P3 | Cancelamento (`/cancel`) do Pix aguardando pagamento | reembolsos e cancelamentos | |
| P4 | Devolução parcial pela transação (`/refund` com `transactions[].id` e `amount`) | reembolsos | |
| P5 | `status_detail` do Pix pendente: `waiting_transfer` ou `waiting_payment` | contradição | |

## Boleto

| # | O que conferir | Por que | Resultado |
|---|---|---|---|
| B1 | O endereço com `street_number = "N/A"` é aceito (a API de pagamentos usa `S/N`) | contradição | |
| B2 | `expiration_time` em dias (`P7D`); vencimento de sábado passa à segunda; a linha digitável traz o fator da segunda | boleto | |
| B3 | A ficha gerada pelo CRM: o código de barras lido por um leitor de verdade e o beneficiário impresso (o credor ou o Mercado Pago?) | lacuna 1 e premissa | |
| B4 | Boleto pago depois do vencimento é mesmo devolvido; para todas as contas | boleto | |
| B5 | Valor mínimo e máximo do boleto e do Pix | lacuna 5 | |

## Cartão

Abra a página `/pagar/<token>` de um link com cartão da integração Mercado Pago, com o console aberto.

| # | O que conferir | Por que | Resultado |
|---|---|---|---|
| K1 | O console não mostra recusa da política de conteúdo; **anote os domínios que o SDK chama de fato** e ajuste `CARD_HOSTS` do adaptador | lacuna 7 | |
| K2 | Os campos de número, validade e código aparecem como quadros do Mercado Pago, com a altura da página | Secure Fields | |
| K3 | A bandeira chega pelo `binChange` e as parcelas mudam | `getPaymentMethods` | |
| K4 | `createCardToken` só com o nome do titular gera token (sem documento) | cartões | |
| K5 | Cartões de teste com titular `APRO`, `OTHE`, `FUND`, `SECU`: pago, recusa geral, saldo, código; os `status_detail` da API Orders e a classificação | lacuna 17 | |
| K6 | Sem 3DS, alguma recusa `3ds_mandatory` | MPG5 | |
| K7 | Parcelas com juros: o pedido mostra o valor cobrado e o total com juros; o CRM registra o valor do instrumento | lacuna 15 | |
| K8 | `GET /v1/payment_methods/installments` aceita `payment_method_id` sem `bin` | MPG13 | |

## Lista de pagos

| # | O que conferir | Por que | Resultado |
|---|---|---|---|
| L1 | `GET /v1/orders` com `status=processed`, `page` e `page_size`: o formato da resposta (`data`, `results`?) e a paginação | busca de pedidos | |
| L2 | Um aviso perdido entra pela lista de pagos (Pix em até 10 minutos, os outros em até uma hora) | MPG11 | |
