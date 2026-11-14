# Roteiro de homologação do adaptador Bradesco (boleto e Pix; incremento 18)

Roteiro **manual**, para quem tem o credenciamento do credor no Bradesco (ambiente de homologação do Pix e o sandbox da API de cobrança). Nenhum teste automático chama o Bradesco: os testes usam um cliente HTTP falso com respostas gravadas à mão a partir dos exemplos dos manuais. Este roteiro confere, uma vez, o que os manuais não dizem ou dizem de dois jeitos. **Não escreva segredos neste arquivo, nem em capturas de tela, nem em logs que vão ao repositório.**

## O que bloqueia antes de começar

- **Boleto (B1): a autenticação da API de cobrança.** O manual 1.6.4 não a descreve. Sem o documento do banco, a peça `Payments::Providers::Bradesco::BoletoAuth::Unconfigured` recusa toda chamada e o boleto do Bradesco não aparece no cadastro de integrações. Quando o documento chegar: guarde-o junto dos manuais do banco, escreva a peça (interface `configured?`, `headers(account, method:, path:, body:)` e `tls(account)`), ligue-a em `Payments::Providers::Bradesco.boleto_auth` no inicializador e acrescente ao manifesto os campos de credencial que ela pedir.
- **Credenciamento (B2).** Pix: gerente de cash management, chave Pix, certificado de cliente com razão social e CNPJ no CN, um por ambiente; inclusão em produção às terças e quintas. Boleto: contrato de cobrança, funcionalidade "175 – Registro via Webservice", primeiro acesso ao Net Empresa, decurso de prazo do contrato em zero (para os "dias para baixa" valerem pela API) e a faixa de nosso número combinada.

## Ligar o webhook (O1, operação)

Os pagamentos chegam pela consulta (lista de pagos) com ou sem webhook. O webhook só encurta o tempo do boleto (de um dia para minutos) e é a rede de segurança do Pix. Para ligar:

1. Certificado do nosso servidor com validade de **um ano** ou mais, de AC pública, com a URL no CN; para o boleto, do tipo **EV ou OV** (o Let's Encrypt de hoje é DV de 90 dias e não serve). Instale-o no nginx do servidor (com cópia da configuração anterior e `nginx -t` antes de recarregar).
2. Boleto: mande o certificado público, zipado, a governancaapis@bradesco.com.br pedindo o cadastro (até 5 dias úteis) e configure o certificado do Bradesco como confiável (baixado no Portal Bradesco Developers, página CERTIFICADOS).
3. Gere o segredo do webhook na integração (tela da integração, "Gerar novo segredo do webhook"), com `CRM_PUBLIC_URL` configurado.
4. Cadastre a URL: `bin/rails "crm:payments:register_webhook[<id da integração>]"`. A integração passa a mostrar "Webhook cadastrado em DD/MM/AAAA". A URL tem `hmac` de 32 caracteres e cabe nos 100 que o cadastro de boleto aceita.
5. Pague um Pix de teste e um boleto de teste e confira que **cada pagamento gera um evento e um pagamento** mesmo chegando pelos dois caminhos: `PaymentEvent.where(account_id: <id>).order(:id).last(5)`.

## Pix (homologação: `qrpix-h.bradesco.com.br`)

Cadastre a integração (fornecedor Bradesco, Pix, ambiente homologação) com Client ID, Client Secret, o `.p12` e a chave Pix; **Testar conexão** pede um token. No console, emita como no roteiro da Efí (`Payments::Issuer.new.request(... kind: "pix", environment: "sandbox")`).

| # | O que conferir | Por que (manual do Pix, "P l.") | Resultado |
|---|---|---|---|
| P1 | O token é aceito com `grant_type=client_credentials` em formulário e Basic, e a URL de produção do token é `https://qrpix.bradesco.com.br/oauth/token` | Só a URL de homologação está no manual (P l. 311) | |
| P2 | Validade do token (`expires_in`) | Não consta (P l. 346) | |
| P3 | `PUT /v2/cobv-emv/{txid}` devolve `{cobv, emv, base64}`; o `base64` é PNG? com prefixo `data:`? | Formato da imagem não consta (P l. 5538). Se não for PNG, o QR Code é gerado aqui | |
| P4 | Segundo `PUT` com o mesmo `txid`: 412 com "4001"? em que campo vem o código? | Idempotência não documentada para a cobv (P l. 1080) | |
| P5 | `GET /v2/cobv/{txid}` devolve `pixCopiaECola`? (necessário quando o P4 cai na consulta) | O exemplo do `PUT /cobv` não traz (P l. 4707-4742) | |
| P6 | Modalidades de multa, juros e desconto aceitas como inteiro (o manual usa texto nos exemplos) | P l. 4129, 4681 | |
| P7 | Desconto com data na véspera do vencimento é aceito | "Menor que o vencimento" (P l. 4210) | |
| P8 | Cancelamento por `PATCH` só com `{"status":"REMOVIDA_PELO_USUARIO_RECEBEDOR"}` | P l. 2392-2394, 5641-5644 | |
| P9 | Devolução: caminho `devolucao` sem acento | O manual escreve `devolução` (P l. 8009) | |
| P10 | Webhook: o banco chama a URL exata ou acrescenta `/pix`? Que IP? Com certificado de cliente? Quantas repetições? | Nada disso consta (P l. 8851-8854; leitura, seção 6) | |
| P11 | Corpo do aviso: `horario` ou `horário`; campos do pagador | Exemplo malformado (P l. 8984-9001) | |
| P12 | `GET /v2/pix?inicio&fim&txIdPresente=true` com paginação traz o Pix pago em até 10 minutos | P l. 8457-8720 | |

## Boleto (sandbox: `openapisandbox.prebanco.com.br`), depois de B1

Cadastre a integração (Bradesco, Boleto) com razão social e CNPJ do beneficiário iguais aos do banco, agência e conta com os dígitos, carteira, espécie e o **nosso número inicial** da faixa combinada. Emita pelo console.

| # | O que conferir | Por que (manual de cobrança, "C l.") | Resultado |
|---|---|---|---|
| B1 | Onde vem o código do registro ("Status-Header": cabeçalho? corpo?) e o HTTP de erro | C l. 1497-1700 | |
| B2 | Registro repetido com o mesmo nosso número responde 69 "Título já cadastrado" | Base da repetição segura (R284f; C l. 1639) | |
| B3 | Percentual de multa e juros: `2.0` (número com casas) é entendido como 2%? | Três formatos no manual (C l. 213, 416-419, 6835-6838) | |
| B4 | `qtdeDiasJuros` e `qtdeDiasMulta` com 1: os encargos começam no dia seguinte ao vencimento? | O "+1" (C l. 515-520) | |
| B5 | Texto do pagador sem acento e cortado em 40 aparece igual na consulta; "SN" é aceito como número | C l. 206-208, 1250-1258, 892 | |
| B6 | A ficha gerada aqui (PDF da integração) passa no leitor de código de barras de um caixa ou aplicativo de banco, e os campos batem com uma 2ª via do Net Empresa | Regras da FEBRABAN fora do manual; dígito do nosso número conferido só com os exemplos da lista (C l. 4073-4140) | |
| B7 | Consulta individual é em tempo real ou D-1? | Lacuna 10 da leitura; se for D-1, o aviso fica "ignorado" e a lista do dia seguinte o reabre | |
| B8 | Formato de `vlrPagto` na consulta (centavos ou reais) | O exemplo traz `0.00` ao lado de `valMoeda` em centavos (C l. 3424-3425) | |
| B9 | Status 56 e 66 a 69: são pagamento? (hoje ficam como ativos) | C l. 3443-3567 | |
| B10 | Baixa repetida: qual a resposta? (o adaptador consulta e aceita se estiver baixado) | C l. 2307 | |
| B11 | Alteração do vencimento com os demais campos em zero não zera multa, juros e desconto | Contradição 11 da leitura (C l. 2353-2377) | |
| B12 | Lista de liquidados: `indMaisPagina` e `paginaAnterior` como no exemplo; data de pagamento em `DDMMAAAA` | C l. 3824-4198 | |
| B13 | Aviso de pagamento: `valorPagamento` igual ao `valorPagamento` da lista do dia seguinte (senão nascem dois eventos para o mesmo pagamento, e o segundo para sem pagar de novo) | Risco do plano; C l. 4005 (oscilação) | |
| B14 | Janela das 00h às 03h: a API responde nela ou não? | C l. 2159-2160 | |
| B15 | Cadastro do webhook: caminho `cadastrar` (sandbox) e `executar` (produção); a URL de 92 caracteres é aceita | C l. 6481-6486, 6525-6570 | |
| B16 | Como o banco se autentica na nossa URL (os erros `CBCA0232` e `CBCA0233` falam de URL de token e client secret que o layout não tem) | C l. 6694-6696 | |
