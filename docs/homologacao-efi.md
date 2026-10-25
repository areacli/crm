# Roteiro de homologação do adaptador Efí (incremento 12, partes B, C e D)

Roteiro **manual**, para quem tem uma conta de desenvolvimento na Efí (ambiente de homologação). Nenhum teste automático chama a Efí: os testes usam um cliente HTTP falso com respostas gravadas à mão. Este roteiro serve para conferir, uma vez, o que a documentação não deixa claro e o que o falso não prova. **Não escreva segredos neste arquivo, nem em capturas de tela, nem em logs que vão ao repositório.**

## O que você precisa

- Conta Efí com a API de cobranças (boleto) e a API Pix habilitadas, no ambiente de **homologação** (hosts `cobrancas-h.api.efipay.com.br` e `pix-h.api.efipay.com.br`).
- Uma aplicação criada na Efí, com **Client ID** e **Client Secret** de homologação e o certificado `.p12` de homologação (baixado do painel da Efí).
- Uma chave Pix cadastrada na conta de homologação.
- O CRM rodando (desenvolvimento), com um credor, um canal de recebimento e um cliente com CPF ou CNPJ válido. Para o endereço do pagador, um contato de endereço válido com CEP.

## Cadastro (aba Contas de pagamento)

1. Crie **duas contas**, ambiente **homologação**, fornecedor **Efí**: uma de **boleto** e uma de **Pix**. Preencha Client ID e Client Secret (em cada uma), o `.p12` e a chave Pix (na de Pix).
2. Em cada conta, clique em **Testar conexão**. Esperado: "Conexão com o fornecedor conferida". Se o `.p12` for antigo (RC2 ou 3DES) e o cadastro recusar o arquivo com "não foi possível abrir", registre aqui o resultado: é a premissa **IP-A2** (o OpenSSL 3 da imagem pode recusar o formato antigo). Saída possível: reexportar o arquivo com o `openssl pkcs12` atual, ou habilitar o provedor legado do OpenSSL na imagem.

## Emissão (console, não há tela)

No console do Rails (`bin/rails console`), com o credor, o cliente e as contas acima:

```ruby
issuer = Payments::Issuer.new
tenant = Tenant.find(...)      # o credor
customer = Customer.find(...)  # o pagador
boleto = issuer.request(tenant: tenant, kind: "boleto", amount_cents: 1000, customer: customer, environment: "sandbox")
pix    = issuer.request(tenant: tenant, kind: "pix", amount_cents: 1000, customer: customer, environment: "sandbox")
```

Com o Sidekiq rodando, os jobs saem sozinhos; sem ele, `Payments::Issuer.new.perform(boleto.reload)`. Em homologação o Pix só confirma valores até R$ 10,00 (1000 centavos).

## O que conferir (e anotar)

| # | O que conferir | Esperado | Premissa |
|---|---|---|---|
| 1 | Boleto: `boleto.reload.state` | `active`, com `digitable_line` preenchida e PDF anexado (`boleto.boleto_pdf.attached?`) | |
| 2 | O PDF baixa **sem** credencial pelo endereço `pdf.charge` da resposta? | Sim. Se a Efí devolver 401/403, o instrumento fica `failed` com "Não foi possível baixar o PDF"; nesse caso o desenho muda (gerar a ficha localmente) | **IP-P2** |
| 3 | O endereço do PDF é de `*.gerencianet.com.br` ou `*.efipay.com.br`? | Sim. Outro domínio é recusado pelo adaptador; registre o domínio real | IP-P2 |
| 4 | `GET /v1/charge/:id` traz o endereço do PDF em `data.payment.banking_billet.pdf.charge` ou em `data.pdf.charge`? | Um dos dois (o adaptador aceita os dois). Se for outro caminho, ajustar `find_pdf_url` | IP-P2 |
| 5 | Multa e juros do boleto: o corpo envia `fine` em centésimos de ponto percentual (200 = 2%) e `interest` como `{value: 100, type: "monthly"}` (1% ao mês). A Efí mostra no boleto 2% e 1% ao mês? | Sim. Se a escala for outra, ajustar `Payloads.billet_configurations` **antes** de usar em produção | |
| 6 | `days_to_write_off` chega ao boleto (padrão 30)? | Sim | |
| 7 | Pix: `pix.reload.state` | `active`, com `copy_paste` e `pix_qr_png` anexado | |
| 8 | `GET /v2/loc/:id/qrcode` devolve `imagemQrcode` em PNG ou em SVG? | A documentação mostra `data:image/svg+xml`. O adaptador só usa PNG; com SVG, o QR Code é gerado aqui a partir do copia e cola. Anote o formato real | **IP-P3** |
| 9 | O QR Code gerado aqui (ou o da Efí) lê no aplicativo do banco e mostra o valor e o recebedor certos? | Sim | |
| 10 | Pix `cobv`: o `devedor` aceita só nome e CPF/CNPJ, ou exige `logradouro`, `cidade`, `uf` e `cep`? Teste com um cliente **sem** endereço | Se exigir, o instrumento fica `failed` com a violação; decidir se o cadastro do cliente precisa do endereço para Pix | |
| 11 | Juros do Pix: modalidade `3` (percentual ao mês, dias corridos) e multa modalidade `2` (percentual). A Efí aceita e calcula certo no Pix pago depois do vencimento? | Sim | |
| 12 | `validadeAposVencimento` (30 dias) é aceito? | Sim | |
| 13 | Mudar o vencimento do boleto: `issuer.change_due_date(boleto, Date.current + 20)` | O vencimento muda na Efí e o PDF é baixado de novo (o SHA-256 muda) | |
| 14 | Cancelar o boleto e o Pix: `issuer.cancel(boleto)` e `issuer.cancel(pix)` | `canceled`; na Efí aparecem cancelados | |
| 15 | Repetição: `issuer.request(..., custom_id: <o mesmo>)` e rodar o job de novo | Não cria cobrança nova na Efí; o Pix reutiliza o `txid` (PUT idempotente) | |
| 16 | Boleto e leitura de rede: derrube a rede no meio de uma emissão de boleto | Falha de conexão que nem saiu: repete. Tempo esgotado ao ler a resposta: o boleto vira `failed` ("o fornecedor não respondeu a tempo") e **pode existir na Efí**: confira no painel antes de emitir outro | |
| 17 | `txid` do Pix: o `custom_id` de 32 caracteres (letras e números) é aceito? | Sim (26 a 35, alfanumérico) | |
| 18 | O token OAuth: cobranças dura 10 minutos, Pix 1 hora. Uma emissão depois de 11 minutos funciona (token renovado)? | Sim | |
| 19 | Credencial errada no teste de conexão | "Credencial recusada pela Efí" | |
| 20 | Nenhum segredo no log (`log/development.log`) nem na mensagem de falha do instrumento | Confirmado por busca no arquivo | |

## Depois

- Registre os resultados (sim/não e o que mudou) no diário da camada, sem segredos.
- O **aviso de pagamento** (webhook do Pix, `notification_url` do boleto e do cartão, token de notificação) e a **conciliação** estão no roteiro da parte D, no fim. O **cartão** está no roteiro da parte C.
- Em produção, repita os itens 1, 7 e 15 uma vez, com valor pequeno, antes de liberar o credor.

## Cartão (parte C): checkout transparente

Pré-requisitos: uma conta de **cartão** da Efí, ambiente homologação (Client ID e Secret da API de cobranças, e o **identificador de conta** `payee_code`, em API > Introdução > Identificador de Conta, que a biblioteca usa no navegador), com o ramo de atividade registrado na conta Efí. Não há tela para criar o link: no console, com a conta de cartão ativa e um cliente com CPF ou CNPJ válido:

```ruby
checkout = Payments::Checkouts.create(tenant: tenant, customer: customer, amount_cents: 1000, card: true, environment: "sandbox")
checkout.token   # abra /pagar/<token> no navegador (HTTPS ou localhost)
```

Na homologação o resultado do cartão sai do **último dígito do número**: 1 dados inválidos, 2 não autorizado por segurança, 3 não autorizado, tentar de novo; os outros aprovam. Use cartões de teste da documentação (bandeira reconhecida pela biblioteca).

| # | O que conferir | Esperado | Premissa |
|---|---|---|---|
| 21 | Com o console de desenvolvimento do navegador aberto na página: aparece **alguma violação** da política de conteúdo (`Refused to connect/load ... Content Security Policy`)? | Nenhuma, exceto, se houver, as do fingerprint antifraude (ver 22). Qualquer domínio novo que a biblioteca acessar: anote e acrescente em `Efi#card_checkout_hosts` | CSP da página |
| 22 | A biblioteca carrega por conta própria o script de fingerprint `device.clearsale.com.br` (terceiro). Com ele bloqueado (extensão ou CSP), o `payment_token` ainda é gerado e a Efí aprova? | Pelo código da biblioteca (3.4.1) o fluxo continua; a Efí pode recusar por antifraude. Decisão do Paulo: manter o domínio liberado (hoje liberado) ou retirar | Decisão registrada |
| 23 | O número digitado mostra as parcelas (`GET /parcelas?brand=` na nossa página, que chama `GET /v1/installments`)? O total com juros confere com o da Efí? | Sim | |
| 24 | Aprovado (cartão final 0): o instrumento `card` fica `active` com `external_id` (charge_id), o link `card_approved` e a página mostra "aprovado". A Efí mostra a cobrança `approved`? | Sim; a confirmação para `paid` vem pela parte D | |
| 25 | Recusas (finais 1, 2 e 3): `refusal.reason` e `refusal.retry` chegam; a mensagem na tela é a nossa, em pt-BR, pelo código (`invalid_data`, `security`, `try_later`)? O texto real da Efí cai na classificação certa? | Sim. Se o texto real for outro, ajustar `Payloads.refusal_code` | |
| 26 | O corpo enviado ao `one-step`: `customer` com `email` e `phone_number` e `billing_address` são **obrigatórios** para cartão? Teste com cliente sem e-mail, sem telefone e sem endereço | Se exigir, o pedido volta 400 com a violação e o cartão não pode ser oferecido sem esses dados; decidir se o link os pede ao pagador (ainda não pede) | |
| 27 | `holderName` e `holderDocument` na biblioteca: o nome digitado é suficiente? | Sim | |
| 28 | Clique duplo no botão e F5 depois de aprovar: uma só cobrança na Efí | Sim (a tentativa é idempotente pelo token) | |
| 29 | Tempo esgotado: com a rede cortada depois do POST, o link vira "não confirmado" e não aceita nova tentativa. A cobrança existe na Efí? | O credor confere no painel; D reconcilia pelo `custom_id` | |
| 30 | `POST /v1/charge/card/:id/refund` com `amount` em **centavos**: a Efí entende centavos? Reembolso parcial e total | Sim. Se o valor for em reais, ajustar `refund_card` | |
| 31 | Devolução de Pix (`PUT /v2/pix/:e2eId/devolucao/:id`, achando o `endToEndId` na cobrança paga): em homologação, devolve? O identificador de devolução derivado do `txid` e do valor é aceito? | Sim | |
| 32 | Nenhum dado de cartão em `log/`, no banco ou na resposta: busque pelos últimos dígitos do cartão de teste | Nada | |
| 33 | A biblioteca (3.4.1) funciona com o navegador dos clientes (celular)? | Sim | |

## Webhooks e conciliação (parte D)

Precisa de um endereço **HTTPS público** para a Efí chamar (um túnel ou o domínio do credor); neste repositório não se mexe em nginx nem em DNS. Configure `CRM_PUBLIC_URL` (sem barra no fim) no ambiente do app e do Sidekiq.

```ruby
# Conta de Pix (a de boleto e a de cartão não precisam de registro: a Efí recebe a URL em cada cobrança).
pix = PaymentAccount.find(<id da conta de Pix>)
pix.rotate_webhook_secret!          # mostra o segredo uma vez; guarde-o. A URL leva só um HMAC derivado dele.
puts Payments::WebhookUrl.for(pix)  # https://<CRM_PUBLIC_URL>/webhooks/pagamentos/contas/<id>?hmac=<64 hex>
```

```sh
bin/rails "crm:payments:register_pix_webhook[<id da conta de Pix>]"  # PUT /v2/webhook/:chave com x-skip-mtls-checking e ?ignorar=
```

As contas de boleto e de cartão precisam do segredo do webhook gerado (tela da conta, "Gerar segredo do webhook") **antes** de emitir: é dele que sai o `hmac` da `notification_url` de cada cobrança. Para ver os avisos chegando: `PaymentEvent.order(:id).last(5)` no console, e o painel do Sidekiq (fila `webhooks`).

| # | O que conferir | Esperado | Premissa |
|---|---|---|---|
| 34 | A cobrança de boleto e a de cartão levam `metadata.notification_url` com o `hmac`? (painel da Efí, cobrança, "Histórico de notificações") | Sim. Sem `CRM_PUBLIC_URL` ou sem segredo gerado a URL não vai e o aviso nunca chega (a conciliação cobre em até 3 dias) | |
| 35 | O POST de cobranças traz o token como formulário (`notification=...`) ou JSON? Chega a `/webhooks/pagamentos/contas/:id?hmac=...` com o `hmac` intacto? | O adaptador lê os dois formatos; a querystring chega inteira | |
| 36 | `GET /v1/notification/:token`: `data[]` vem na ordem dos eventos? `value` está em **centavos**? `received_by_bank_at` é a data do pagamento? Há `custom_id`? | Sim. Se `value` vier em reais, ajustar `expand_notification` (hoje só serve de pista e a consulta da cobrança manda no valor) | |
| 37 | Boleto pago em homologação (simulação do painel): o aviso vira `PaymentEvent` `applied`, o instrumento `paid`, o `Payment` existe no canal da conta, o título está baixado e `instrument.payment` aponta para ele | Sim, em segundos | |
| 38 | Boleto marcado como pago **manualmente** no painel da Efí (`settled`): a notificação diz `settled`? O CRM baixa o título (decisão 70)? | Baixa. Se o credor não quer baixa sem dinheiro, tratar `settled` como `other` em `Payloads::BILLET_STATUS` | |
| 39 | Pix `cobv` de até R$ 10,00 pago em homologação: o webhook chega a `/webhooks/pagamentos/contas/:id` (com ou sem `/pix`) e é aceito (202)? | Sim; evento `applied`, pagamento com o `endToEndId` como identificador | IP-P4 |
| 40 | De que **IP** chega o POST do Pix (homologação e produção)? O app enxerga esse IP em `request.remote_ip` (atrás do nginx, com o proxy confiável)? | `34.193.116.226`. Outro IP = 401 ("webhook_refused" nos acessos) até ajustar `PAYMENTS_WEBHOOK_IPS` (lista separada por vírgula) | IP-P4 |
| 41 | O registro com `?ignorar=` impede a Efí de acrescentar `/pix`? E sem ele, a rota com `/pix` chega ao mesmo lugar? | Sim, as duas | |
| 42 | Ao registrar, a Efí manda uma notificação de teste: qual corpo? O CRM responde 2xx sem criar evento? | 202 com `events: 0` (corpo sem `pix[]` nem token) | |
| 43 | Reenvio manual (`POST /v2/gn/webhook/reenviar`, `tipo: PIX_RECEBIDO`, o mesmo `endToEndId`) | Um só evento (índice único); nenhum pagamento novo | |
| 44 | Tempo de resposta do endpoint sob chamada real | Bem abaixo dos 60 s da Efí (o controlador só grava e enfileira) | |
| 45 | `valor` no webhook do Pix é texto em reais ("110.00"); o Pix pago com juros e multa traz `valor` maior que o original? A consulta `GET /v2/cobv/:txid` mostra `pix[].valor` igual? | O CRM baixa o valor consultado; a diferença vira crédito do contrato | IP-P6 |
| 46 | Devolução de Pix (`refund_pix` no console): o webhook de devolução chega (`pix[].devolucoes[]`, `status` `DEVOLVIDO`)? O CRM registra o estorno com o valor certo e o título volta à cobrança? Uma devolução `NAO_REALIZADO` não estorna | Sim | |
| 47 | Reembolso de cartão (`refund_card`): a notificação diz `refunded`; a consulta `GET /v1/charge/:id` mostra `refunded` e o valor? **Reembolso parcial** aparece de alguma forma? | Total sim; parcial a confirmar (o CRM só enxerga o total) | |
| 48 | Cartão aprovado: quais notificações chegam (`approved`, `paid`) e em quanto tempo? O link passa a pago e a tela do cliente se refaz (Action Cable)? | Sim | |
| 49 | O horário (`horario`, UTC) vira a data de pagamento certa (fuso de Brasília), nunca maior que hoje? Pix pago às 22h de Brasília cai no dia certo? | Sim | |
| 50 | Conciliação: pare o endpoint (ou apague o aviso), pague um boleto e rode `PAYMENTS_RECONCILE_AFTER_DAYS=0 bin/rails "crm:payments:reconcile[<id do credor>]"` com o Sidekiq ligado | O instrumento é baixado pela consulta; o `TaskRun` `payment_reconciliation` mostra quantos | |
| 51 | Cartão "não confirmado" (rede cortada depois do POST): a Efí cria a cobrança e manda a notificação com o nosso `custom_id`; o CRM adota o `charge_id` e baixa | Sim | |
| 52 | Nenhum segredo, token de notificação além do necessário, dado do pagador ou de cartão em `log/` ou em `payment_events` (busque o CPF e o nome do pagador de teste) | Nada | |
