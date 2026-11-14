# Roteiro de homologação do adaptador PagBank (boleto, Pix e cartão; incremento 19)

Roteiro **manual**, para quem tem a conta de sandbox do PagBank e, depois, a conta de produção de um credor. Nenhum teste automático chama o PagBank: os testes usam um cliente HTTP falso com respostas gravadas à mão a partir dos exemplos do portal (`developer.pagbank.com.br`, lido em 14/11/2026). Este roteiro confere, uma vez, o que o portal não diz ou diz de dois jeitos. **Não escreva segredos neste arquivo, nem em capturas de tela, nem em logs que vão ao repositório.**

## Antes de começar

1. **Conta de sandbox** no Portal do Desenvolvedor do PagBank e uma **aplicação Connect** da instalação em cada ambiente (`POST /oauth2/application`, com o `redirect_uri` fixo `https://<endereço público>/configuracao/integracoes/conexao/retorno`). Guarde o `client_id`, o `client_secret` e o token da conta da plataforma nas credenciais cifradas do Rails (`payments.connect.pagbank.sandbox` e `.production`, campos `client_id`, `client_secret`, `platform_token`) ou nas variáveis `CRM_CONNECT_PAGBANK_<AMBIENTE>_<CAMPO>`. Sem isso, a integração diz que a instalação não tem a aplicação e não oferece "Conectar".
2. **Homologação do PagBank** (obrigatória para integração própria): formulário do PagBank com os registros de pedido e resposta do sandbox e da produção; até 4 dias úteis. Antes dela, a produção responde 403.
3. **`CRM_PUBLIC_URL`** com o endereço público em HTTPS: é para onde o PagBank volta na autorização e para onde manda os avisos.
4. **SDK do cartão:** o arquivo `src/vendor/javascript/pagbank-checkout-sdk.js` não vai ao repositório público (o PagBank não declara licença). Numa cópia do repositório público, rode `bin/rails "crm:payments:card_sdk[pagbank]"`: a tarefa baixa o arquivo do PagBank e só o grava se o SHA-256 for o do adaptador. O portal do PagBank barra acesso automático (Cloudflare): se a tarefa receber 403, baixe o arquivo pelo navegador, confira o SHA-256 (`sha256sum`) e grave-o no mesmo caminho. SHA-256 diferente quer dizer que o PagBank trocou o arquivo: leia, teste e troque o SHA-256 no adaptador antes de usar.

## Conexão (Connect)

Cadastre a integração (fornecedor PagBank, ambiente homologação). Ela nasce sem credencial digitada e com a chave da URL do aviso. Clique **Conectar ao PagBank**, autorize na página do PagBank e volte.

| # | O que conferir | Por que (portal) | Resultado |
|---|---|---|---|
| C1 | A volta traz `code` e `state`; a integração mostra "Conectada em DD/MM/AAAA" e o histórico registra a conexão | Connect, autorização | |
| C2 | Qual token vai no `Authorization` da troca do código (o da conta da plataforma, pela forma da página) e se `X_CLIENT_ID` e `X_CLIENT_SECRET` são esses nomes exatos | lacuna 9 | |
| C3 | A duração do `access_token` e o nome do campo de expiração na resposta (`expires_in` em segundos? data?) | lacuna 9 | |
| C4 | Renovar (`grant_type=refresh_token`) devolve um `refresh_token` novo e o antigo para de valer | Connect | |
| C5 | Os escopos `payments.read payments.create payments.refund` bastam para pedido, consulta, reembolso, chave pública e taxas | Connect | |
| C6 | **Testar conexão** responde "boa" (consulta de um pedido inexistente, 404) | — | |

## Pix (sandbox: `sandbox.api.pagseguro.com`)

No console: `Payments::Issuer.new.request(tenant:, kind: "pix", amount_cents:, customer:, object:, environment: "sandbox")`. O simulador decide pelo valor: até R$ 100,00 paga na hora; até R$ 200,00, em 5 minutos; até R$ 300,00, fica aguardando; até R$ 400,00, recusa.

| # | O que conferir | Por que (portal) | Resultado |
|---|---|---|---|
| P1 | O pedido com `qr_codes[]` e `expiration_date` é aceito; a resposta traz `qr_codes[0].text` | contradição "onde vai o Pix" | |
| P2 | Validade máxima aceita para `expiration_date` (o vencimento pode estar a 30 dias?) | lacuna 3 | |
| P3 | O nome do cabeçalho de idempotência: mande o mesmo pedido duas vezes com `x-idempotency-key` igual e veja se o segundo devolve o mesmo pedido ou o erro `40005`. **Se confirmar, troque `repeatable_issue` do manifesto para `%w[pix boleto]`** e o nome em `IDEMPOTENCY_HEADER` | lacuna 1 | |
| P4 | O aviso chega na URL do pedido, com `?hmac=` intacto; em que formato vem o Pix (dentro da cobrança ou `qr_code[]` no pedido) | contradição "formato do Pix no aviso" | |
| P5 | Pix pago: `charges[0].status = PAID`, `amount.summary.paid` e `payment_method.pix.end_to_end_id` | Pix | |
| P6 | Pix não pago até a validade: o pedido mostra a cobrança `CANCELED` (o CRM lê como vencido) ou só o QR Code vencido | Pix | |
| P7 | Pix recusado (R$ 300,01 a R$ 400,00): o instrumento falha "recusado pela análise de risco" | simulador | |
| P8 | Devolução parcial: `POST /charges/{id}/cancel` com `amount.value`; o aviso traz `summary.refunded` e vira estorno | cancelar | |
| P9 | Existe cancelamento de Pix não pago? Se existir, troque `cancel` do manifesto | lacuna 2 | |

## Boleto

| # | O que conferir | Por que (portal) | Resultado |
|---|---|---|---|
| B1 | O pedido com `template: "cobranca"` e `payment_instructions` (multa e juros em D+1, percentual vezes 100) é aceito; ou se é `COBRANCA` | contradição "modelo do boleto" | |
| B2 | Juros: o percentual é ao mês ou ao dia | lacuna 5 | |
| B3 | `holder.email` é obrigatório (o CRM não manda e-mail no boleto) | lacuna 6 | |
| B4 | `days_until_expiration` como texto (`"30"`) é aceito e quer dizer "dias depois do vencimento" | contradição | |
| B5 | O link do PDF vem em `boleto.pagseguro.com.br` também no sandbox (o exemplo mostra links de produção); baixa sem `Authorization` | contradição "exemplo em sandbox" | |
| B6 | Boleto recusado (`DECLINED`) traz os campos onde | contradição "boleto recusado" | |
| B7 | Existe cancelamento de boleto não pago ou troca de vencimento? Se existir, troque `cancel` e `due_date_change` do manifesto | lacunas 2 | |
| B8 | Boleto pago: aviso e consulta com `PAID` e `summary.paid`; o pagamento entra e baixa o título | — | |

## Cartão

Abra a página `/pagar/<token>` de um link com cartão da integração PagBank, no navegador, com o console aberto.

| # | O que conferir | Por que (portal) | Resultado |
|---|---|---|---|
| K1 | O console não mostra recusa da política de conteúdo: o SDK carrega do nosso domínio, com `integrity`, e o `encryptCard` não chama rede | SDK lido | |
| K2 | O pedido ao servidor (aba Rede) leva só `payment_token` (o cartão cifrado), `installments` e `brand` | R284t | |
| K3 | O PagBank aceita o cartão sem 3DS para este perfil de cobrança | lacuna 11 | |
| K4 | `GET /charges/fees/calculate` sem `credit_card_bin` devolve os planos por bandeira, e em que aninhamento | taxas | |
| K5 | Parcelado com juros: o PagBank aceita `amount.value` com juros e `amount.fees.buyer.interest`; o pagamento entra pelo valor do instrumento | R284v | |
| K6 | Cobrança em análise (`IN_ANALYSIS`): a página mostra "em análise" e o aviso a conclui | R284u | |
| K7 | Recusas: os códigos de `payment_response.code` batem com a tabela de motivos | motivos de compra negada | |
| K8 | A chave pública (`POST /public-keys`, `type: card`) sai com o token do Connect | lacuna 9 | |

## Avisos e consulta

| # | O que conferir | Por que (portal) | Resultado |
|---|---|---|---|
| A1 | Qual token compõe o `x-authenticity-token` numa conta do Connect (o CRM não confere hoje; confere o `hmac` da URL) | lacuna 7 | |
| A2 | Retentativa dos avisos e IPs de origem | lacuna 8 | |
| A3 | O formato antigo (`notificationCode`) chega para devolução, chargeback e saldo e vira "para conferir" | avisos | |
| A4 | Aviso perdido: a conciliação das 7h20 confere todo ativo depois de 1 dia e o pagamento entra | R284r | |
| A5 | Limite de requisições: 429 ou `40004` num lote; o lote repete com espera | lacuna 13 | |
| A6 | Leiaute do EDI e se ele identifica a cobrança (para a lista de pagos, que ainda não existe) | lacuna 12 | |
