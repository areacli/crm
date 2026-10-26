<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/logotipo-crm-negativo.svg">
    <img src=".github/logotipo-crm.svg" alt="CRM AreaCli" width="320">
  </picture>
</h1>

CRM de cobrança: um credor importa a carteira de clientes e títulos a partir de planilhas, acompanha quem deve e quanto, registra os pagamentos e os estornos recebidos pelos seus canais (por planilha ou por webhook assinado), registra os contatos feitos com cada cliente, mantém o cadastro do credor e os vários contatos de cada cliente, controla quem acessa o quê e mantém o histórico de cada alteração. Vários credores convivem no mesmo sistema, e cada pessoa vê só os credores em que tem permissão.

O projeto é desenvolvido por incrementos, cada um a partir de uma especificação aprovada antes do código. A discussão de cada incremento é contada na série [Criei um CRM](https://blog.areacli.com/criei-um-crm/), no Blog AreaCli.

## Demonstração

https://crm.areacli.com, com dados fictícios recriados todo dia às 4h (horário de Brasília). Os arquivos enviados são descartados sem ser lidos e trocados por arquivos fictícios; o que é digitado em campo livre é trocado por texto fictício; nenhum fornecedor de pagamento real é chamado.

| Usuário | Senha | O que pode fazer |
|---|---|---|
| `gestor@demo.crm.areacli.com` | `demonstracao-gestor` | Gestor na Escola Alfa e operador na Clínica Beta: importar e confirmar carteira, pagamentos e estornos; registrar acionamentos; aprovar promessas e acordos; canais de recebimento, políticas de pagamento, segmentos e encargos; transferir crédito entre contratos; direitos do titular. Usuários, perfis, senhas, dados do credor e contas de pagamento ficam fechados (só leitura) |
| `operador@demo.crm.areacli.com` | `demonstracao-operador` | Operador na Escola Alfa (a Clínica Beta não aparece): consultar clientes e fichas, registrar acionamentos, editar o cadastro do cliente e negociar acordos |

A carteira da Escola Alfa tem 10 mil clientes com títulos desde 2020, pagamentos, estornos, acionamentos, promessas nos oito estados, acordos nos estados principais, divergências de valor, um cliente anonimizado e instrumentos de pagamento do fornecedor falso. A página pública de pagamento de exemplo (sem login) fica em `/pagar/demonstracao-pagamento`; no cartão de teste, o último dígito do número escolhe o resultado (1 dados inválidos, 2 recusa, 3 recusa que pode repetir, qualquer outro aprova). A demonstração roda com `CRM_DEMO=1`; os dados vêm da tarefa `bin/rails crm:demo_data` (e `crm:demo_reset` recria tudo).

## Telas

Estado atual da aplicação em Rails (fotos recriadas a cada incremento por `deploy/rails/capturas.sh`).

| | |
|---|---|
| ![Resumo da carteira](docs/telas/resumo.png) | ![Lista de clientes](docs/telas/clientes.png) |
| Resumo da carteira: totais somados dos credores a que a pessoa tem acesso, faixas de atraso por cliente e por título (quando iguais), valor atualizado e segmentos | Lista de clientes com busca, filtros e ordenação |
| ![Ficha do cliente](docs/telas/ficha-do-cliente.png) | ![Conferência da importação da carteira](docs/telas/conferencia-da-carteira.png) |
| Ficha do cliente: dados, totais e títulos | Conferência antes de confirmar a carga: o que entra, o que sai, as linhas recusadas e os acréscimos informados comparados com os calculados |
| ![Importações](docs/telas/importacoes.png) | ![Importar carteira](docs/telas/importar-carteira.png) |
| Importações do credor, com o andamento em tempo real | Envio da planilha, com a tabela de colunas e a planilha-modelo |
| ![Configuração da carteira](docs/telas/configuracao.png) | ![Usuários do credor](docs/telas/usuarios.png) |
| Faixas de atraso e tratamento do a vencer, por credor | Usuários e seus perfis em cada credor |
| ![Perfis de permissões](docs/telas/perfis.png) | ![Importar pagamentos](docs/telas/importar-pagamentos.png) |
| Perfis com as 16 permissões | Envio da planilha de pagamentos (e a de estornos), com colunas e planilha-modelo |
| ![Conferência de pagamentos](docs/telas/conferencia-de-pagamentos.png) | ![Canais de recebimento](docs/telas/canais-de-recebimento.png) |
| Conferência antes de confirmar: quitados, baixas parciais, créditos, pendentes e ignorados | Canais de recebimento do credor, em uma aba da configuração |
| ![Canal de recebimento](docs/telas/canal-de-recebimento.png) | ![Políticas de pagamento](docs/telas/politicas-de-pagamento.png) |
| Canal: dados e webhook de pagamento assinado | Políticas de pagamento por credor |
| ![Ficha com pagos e crédito](docs/telas/ficha-com-pagos-e-credito.png) | ![Ficha com acionamentos](docs/telas/ficha-com-acionamentos.png) |
| Ficha: pagamentos aplicados e crédito por contrato, com transferência entre contratos | Ficha: formulário de acionamento e histórico |
| ![Lista de acionamentos](docs/telas/acionamentos.png) | ![Resultados de acionamento](docs/telas/resultados-de-acionamento.png) |
| Lista de acionamentos dos credores, com filtros e paginação | Resultados de acionamento por credor, em uma aba da configuração |
| ![Divergências de valor](docs/telas/divergencias-de-valor.png) | ![Divergência de valor](docs/telas/divergencia-de-valor.png) |
| Divergências de valor: títulos com pagamento cujo valor o credor mudou numa carga, para o financeiro tratar | Detalhe da divergência: o que mudou, o efeito aplicado e o tratamento com nota |
| ![Histórico do título](docs/telas/historico-do-titulo.png) | ![Ficha com contatos](docs/telas/ficha-com-contatos.png) |
| Histórico do título: versões do valor, pagamentos, estornos e divergências em ordem de data | Ficha: contatos do cliente com situação e origem, ações de edição, histórico do cadastro e contratos com os papéis |
| ![Dados do credor](docs/telas/dados-do-credor.png) | ![Política de correção na tela ou carga](docs/telas/politica-de-correcao.png) |
| Dados do credor (CNPJ, razão social, endereço, contatos) e prazo de guarda, um cartão por credor | Correção na tela ou carga: qual vale, por credor, na aba Carteira |

| | |
|---|---|
| ![Guarda de dados](docs/telas/guarda-de-dados.png) | ![Exportação dos dados do cliente](docs/telas/exportacao-de-dados.png) |
| Guarda de dados: prazo, anonimização prevista nos próximos 30 dias, retidos e execuções da tarefa diária | Dados do cliente para imprimir ou baixar em JSON (direito de acesso) |
| ![Ficha de cliente anonimizado](docs/telas/ficha-anonimizada.png) | ![Segmentos](docs/telas/segmentos.png) |
| Ficha de cliente anonimizado: só restam os dados que não identificam a pessoa | Segmentos e encargos do credor, em ordem, com critérios, a regra de encargos de cada um, parâmetros e políticas do credor |
| ![Conferência de segmentos](docs/telas/conferencia-de-segmentos.png) | ![Novo segmento](docs/telas/novo-segmento.png) |
| Conferência do impacto antes de a mudança valer: quantos contratos entram, de onde vêm e o saldo | Critérios do segmento: atraso, saldo, títulos vencidos, percentual vencido, clientes, idade, tipo, produto e acordo quebrado |
| ![Índices do Banco Central](docs/telas/indices.png) | ![Ficha com segmentos](docs/telas/ficha-com-segmentos.png) |
| Índices IPCA, INPC, IGP-M, Selic e taxa legal mês a mês, com a correção do credor e a situação da busca | Ficha: faixa de atraso e segmento de cada contrato, com o histórico de segmento |
| ![Ficha com valor atualizado](docs/telas/ficha-com-valor-atualizado.png) | ![Regra de encargos do segmento](docs/telas/regra-de-encargos.png) |
| Ficha: valor atualizado de cada título com os componentes e a memória de cálculo (períodos, segmento, índices, taxas e dias) | Regra de encargos no formulário do segmento: multa, juros, correção, honorários, convenção de dias e base da multa, com o que herda do credor |
| ![Conferência de encargos](docs/telas/conferencia-de-encargos.png) | ![Ficha com promessas](docs/telas/ficha-com-promessas.png) |
| Conferência do impacto: o valor atualizado por segmento antes e depois da mudança, e o aviso do CDC para multa acima de 2% | Ficha: uma linha por promessa aberta ou pendente sob o resumo, com as ações de aprovar, recusar e cancelar |
| ![Registrar promessa](docs/telas/formulario-de-promessa.png) | ![Promessas pendentes](docs/telas/promessas-pendentes.png) |
| Formulário do acionamento: títulos de um contrato, meio e data prometida, com o valor de cada título na data antes de gravar | Lista de promessas pendentes de aprovação, para quem tem alçada nos credores em que a promessa foi feita |
| ![Configuração das promessas e dos acordos](docs/telas/configuracao-de-promessas.png) | ![Simulação de acordo](docs/telas/simulacao-de-acordo.png) |
| Promessas e acordos: políticas do credor, prazo máximo e alçada das promessas; políticas dos acordos, variáveis de cada segmento e limites de cada perfil, com as alterações recentes | Simulação do acordo na ficha: títulos, descontos por componente, entrada e parcelas, com a base, o valor do acordo, a taxa efetiva e a tabela de parcelas antes de gravar |
| ![Proposta de acordo](docs/telas/proposta-de-acordo.png) | ![Termo do acordo](docs/telas/termo-do-acordo.png) |
| Proposta aprovada: resumo, títulos com a base e o desconto por componente, parcelas, ações da alçada e o registro do aceite | Termo para imprimir ou salvar em PDF: partes, dívidas renegociadas, parcelas, taxa efetiva anual, soma total e as condições congeladas |
| ![Acordo aguardando efetivação](docs/telas/acordo-aguardando-efetivacao.png) | ![Lista de acordos](docs/telas/lista-de-acordos.png) |
| Acordo aceito: quem aceitou e com que papel, o canal, o comprovante e o histórico | Lista de acordos por credor, com filtros de situação, período e quem montou, e os casos que pedem o gestor |
| ![Acordos pendentes](docs/telas/acordos-pendentes.png) | ![Ficha com acordos](docs/telas/ficha-com-acordos.png) |
| Propostas pendentes que a pessoa pode aprovar, pelos limites atuais do perfil dela | Ficha: a proposta numa linha sob o resumo, o histórico dos acordos e o título preso à proposta |
| ![Parâmetros dos acordos](docs/telas/parametros-dos-acordos.png) | ![Acordo efetivado](docs/telas/acordo-efetivado.png) |
| Segmentos e encargos: juros e método do parcelamento, convenção de dias e base da multa dos títulos de acordo, do credor e de cada segmento | Acordo efetivado: os títulos de acordo com o devido de hoje (com a mora dos parâmetros congelados), o cálculo da quitação e a quebra manual |
| ![Acordo quebrado](docs/telas/acordo-quebrado.png) | ![Ficha com títulos de acordo](docs/telas/ficha-com-titulos-de-acordo.png) |
| Acordo quebrado: o motivo, a forma da quebra e os títulos que seguem em cobrança | Ficha: o título de acordo com a marca, o original renegociado e o saldo devedor do acordo |
| ![Arquivo de acordos](docs/telas/arquivo-de-acordos.png) | ![Acordo em reversão](docs/telas/acordo-em-reversao.png) |
| Arquivo de acordos: exportar as novidades ou o completo para o credor emitir a entrada e as parcelas, com as exportações dos últimos 30 dias | Acordo em reversão: a marca, as liquidações estornadas e os botões de concluir ou desistir; o crédito vira aguardando alocação |
| ![Ficha com crédito por estado](docs/telas/ficha-com-credito-por-estado.png) | ![Estornos à espera do gestor](docs/telas/estornos-a-espera.png) |
| Ficha: o crédito do contrato por estado (disponível, aguardando alocação, bloqueado) e a alocação num título do mesmo contrato | Estornos à espera do gestor: há quanto tempo esperam, as opções que o estado permite e a decisão com motivo |
| ![Simulação de acordo sobre acordo](docs/telas/simulacao-de-acordo-sobre-acordo.png) | |
| Acordo sobre acordo: os títulos do acordo quebrado entram pelo saldo devedor, com os juros do parcelamento e os encargos de atraso herdados | |

| | |
|---|---|
| ![Contas de pagamento](docs/telas/contas-de-pagamento.png) | ![Nova conta de pagamento](docs/telas/nova-conta-de-pagamento.png) |
| Contas de pagamento por credor, modalidade e ambiente, em uma aba da configuração | Cadastro montado pelo manifesto do fornecedor: segredos em branco, certificado enviado como arquivo |
| ![Conta de pagamento](docs/telas/conta-de-pagamento.png) | |
| Conta com certificado (titular, validade e impressão digital), teste de conexão, segredo do webhook e histórico sem valores | |
| ![Pagamento do cliente](docs/telas/pagamento-do-cliente.png) | |
| Página pública de pagamento do cliente (link com token, sem login): Pix com QR Code local, boleto e cartão por checkout transparente; os campos do cartão não são enviados ao servidor | |

### Demonstração carregada

Fotos da demonstração com os dados fictícios completos (10 mil clientes, pagamentos, promessas e acordos), tiradas pela V5 (`deploy/rails/v5/v5-demo.mjs`) em 25/10/2026.

| | |
|---|---|
| ![Resumo com os totais dos dois credores](docs/telas/demonstracao-resumo.png) | ![Lista de clientes](docs/telas/demonstracao-clientes.png) |
| Resumo da carteira com os totais da Escola Alfa e da Clínica Beta somados, a faixa da demonstração e o recuperado por meio de pagamento | Lista de clientes com a carteira de 10 mil clientes |
| ![Acionamentos](docs/telas/demonstracao-acionamentos.png) | ![Divergências de valor](docs/telas/demonstracao-divergencias-de-valor.png) |
| Lista de acionamentos dos últimos 120 dias | Divergências de valor a tratar pelo financeiro |
| ![Acordos](docs/telas/demonstracao-acordos.png) | ![Promessas pendentes](docs/telas/demonstracao-promessas-pendentes.png) |
| Propostas e acordos nos estados principais, com os casos que pedem o gestor | Promessas pendentes de aprovação |
| ![Segmentos e encargos](docs/telas/demonstracao-configuracao-segmentos.png) | ![Importações](docs/telas/demonstracao-importacoes.png) |
| Segmentos de contratos e as regras de encargos | Importações, com a carga conferida à espera de confirmação |
| ![Página de pagamento](docs/telas/demonstracao-pagar.png) | |
| Página pública de pagamento de exemplo, com Pix (QR Code gerado aqui), boleto e cartão | |

## Incrementos

O projeto foi refeito em Ruby on Rails 8.1 (decisão de 24/10/2026), um incremento por vez, na ordem das especificações.

| Incremento | O que entrega | Em Rails |
|---|---|---|
| 1. Carteira | Credores (tenants), importação da carteira por planilha CSV com conferência antes de confirmar (incremental ou carga completa), contratos, lista de clientes com faixas de atraso, ficha e resumo | feito |
| 2. Perfis e usuários | Perfis com permissões por credor, usuários identificados pelo e-mail, senha temporária, troca da própria senha, ligação de um usuário existente a outro credor, histórico de acessos e sino de avisos | feito |
| 3. Pagamentos e baixa | Canais de recebimento, importação de pagamentos e estornos com conferência, baixa total, parcial ou crédito do contrato, políticas de pagamento do credor, transferência de crédito, recuperado no resumo e webhook de pagamento (HMAC SHA-256, idempotente, sem provedor) | feito |
| 4. Acionamentos | Registro de contatos na ficha do cliente (canal, contato usado, resultado da lista do credor, retorno conforme a regra do resultado, texto), histórico imutável que se atualiza quando outro operador registra, lista de acionamentos com filtros, resultados configuráveis por credor e números no resumo | feito |
| 5. Carteira revista | Valor do título em versões, saldo sempre calculado e nunca negativo, excedente de valor reduzido como crédito do contrato, divergência de valor com política do credor (seguir o valor novo ou manter e registrar), lista do financeiro com tratamento por nota, histórico do título, produto e acréscimos informados pelo credor na planilha | feito |
| 6. Cadastros | Dados do credor (CNPJ validado e único, razão social, endereço, contatos), vários contatos por cliente (telefone, e-mail e endereço) com origem, situação (válido, inválido, não perturbe) e histórico, edição pela ficha por quem tem a permissão no credor, colunas de contato na planilha, política "a tela prevalece" ou "a carga vence" por credor, contato igual ao do credor entra inválido, sugestões e "salvar no cadastro" no acionamento | feito |
| 7. Direitos do titular | Exportar os dados de um cliente (página para imprimir e JSON), anonimizar a pedido ou depois do prazo de guarda do credor (nome, documento, contatos, textos e histórico; valores e datas ficam), relação em aberto que impede, retenção com motivo, previsão dos próximos 30 dias, tarefa diária por credor | feito |
| 8. Índices e segmentos | Índices IPCA, INPC, IGP-M e Selic buscados todo dia no Banco Central (globais, com mês corrente parcial, falha na tela e "Buscar índices agora"), correção do índice por credor com motivo, segmentos de contratos por credor com critérios combinados (atraso, saldo, títulos e valor vencidos, clientes, idade, tipo PF, PJ ou misto, produto, acordo quebrado), conferência do impacto antes de valer, recálculo diário e depois da carga, histórico por contrato, coluna e filtro de segmento na lista e segmento de cada contrato na ficha | feito |
| 9. Encargos e valor atualizado | Regra de encargos por segmento (multa, juros de taxa fixa simples ou compostos ou taxa legal, correção por IPCA, INPC ou IGP-M, honorários) com parâmetros do credor que o segmento herda, cinco políticas do credor (mês sem índice, forma dos juros, índice negativo, juros legais antes de 30/08/2024, comparação dos acréscimos da carga), taxa legal (série 29543) entre os índices, valor atualizado de cada título vencido recalculado todo dia e a cada mudança, conferência do impacto antes de a regra valer, ficha com componentes e memória de cálculo, coluna na lista, cartão por credor no resumo e baixa dos pagamentos por componente (juros, multa, honorários, correção e principal, nessa ordem) | feito |
| 10. Promessas de pagamento | Resultado "Prometeu pagar" e a marca "admite promessa", promessa registrada junto do acionamento (títulos de um contrato, meio e data, com o valor de cada título na data prometida e sem isenção nem desconto), alçada de prazo por perfil e segmento com aprovação e recusa, número `PRM-` dado quando fica aberta, pagamento ligado à promessa pelo número no arquivo de pagamentos (encargos antes do principal), cumprimento, cumprimento com atraso, quebra pela tarefa diária com o percentual pago, reabertura no estorno, cancelamento com motivo, seis políticas do credor, ficha com a linha da promessa, lista de pendentes, filtro na lista de clientes e cartão de promessas no resumo | feito |
| 11. Acordos | Acordos por novação. Parâmetros do parcelamento e da mora com override no segmento, feriados e municípios do IBGE com a praça do cliente, estado final "quitado" e tolerância de valor com abatimento, motor dos encargos do título de acordo; variáveis de acordo do segmento, limites por perfil e 33 políticas do credor, simulação (sem juros, Price e SAC, primeiro período irregular, descontos por componente, crédito do contrato), alçada com aprovação e recusa, validade, termo para imprimir e aceite; **títulos de acordo na carteira** (entrada e parcelas com a composição dos originais), efetivação pelo pagamento da entrada ou pelo aceite, pagamento pelo número com mora, tolerância, mínimo e desconto da antecipação, quitação antecipada, cancelamentos automáticos, arquivo de acordos para o credor; **quebra** pela tarefa diária (antes e depois da efetivação, "parcelas seguem" ou título único), reativação pelo pagamento no prazo, quebra manual e a marca "já quebrou acordo"; **estornos e reversão**: estorno bancário que reabre a parcela (prazo novo), título de estorno fora do acordo, estorno à espera do gestor com decisão e crédito bloqueado, teste da soma do acordo encerrado, estorno da quitação antecipada, reversão em dois passos com crédito aguardando alocação (alocar ou transferir) e desistência, crédito por estado, "Usar crédito", as opções automáticas do crédito na tarefa diária, o cartão de acordos no resumo; **acordo sobre acordo** com juros do parcelamento e encargos de atraso herdados e a renegociação do anterior; dados pessoais dos acordos na exportação e na anonimização. Fora: a promessa sobre título de acordo | feito |
| 12. Instrumentos de pagamento | Boleto, Pix e cartão com fornecedores intercambiáveis (o credor escolhe o de cada modalidade; o falso e a Efí, só o manifesto, hoje). Parte A: contas de pagamento por modalidade e ambiente com formulário montado pelo manifesto do fornecedor, certificado .p12 validado e cifrado (só titular, validade e impressão digital voltam para a tela), troca de segredos com histórico sem valor, teste de conexão, aviso 30 dias antes do vencimento do certificado, e chaves do Active Record Encryption em credenciais cifradas com rotação em lotes (`crm:encryption:rotate`). Parte B: emissão de boleto e Pix só por serviço (idempotente pelo identificador nosso, em lote com limite de taxa, cancelar e mudar vencimento), PDF e QR Code guardados em disco (Active Storage sem rotas públicas, SHA-256 conferido) e entregues só por rotas autenticadas com a permissão do credor, adaptador Efí para boleto e Pix (OAuth, mTLS com o .p12 em memória, testado só com respostas gravadas; roteiro de homologação em `docs/homologacao-efi.md`). Parte C: link de checkout criado só por serviço e página pública `/pagar/:token` (sem login, com limite de requisições, sem cache nem indexação, política de segurança de conteúdo própria que libera só o que o adaptador declara), Pix e boleto servidos daqui, cartão só por checkout transparente com a biblioteca do fornecedor fixada no repositório (os campos do cartão não têm `name`: o servidor recebe só o `payment_token` e as parcelas), cobrança idempotente, recusas em pt-BR, página que se refaz por Action Cable com canal por token, adaptador Efí de cartão. Parte D: webhook por conta de pagamento (autenticado pelo adaptador: HMAC do corpo, ou, na Efí, certificado do proxy ou HMAC na URL com o IP), aviso guardado uma vez por identificador, job na fila `webhooks` que consulta o fornecedor antes de mudar o instrumento e entra pelo mesmo caminho do pagamento (baixa pelas políticas do credor, encargos por componente, promessas e acordos pelo número), estorno de Pix devolvido e cartão reembolsado, reprocessagem dos avisos que falharam e conciliação diária dos instrumentos ativos. Não há tela de emissão nem de cartão | feito (partes A a D) |

## Tecnologia

Ruby 4.0 e Rails 8.1 "completamente semântico": HTML e CSS semânticos, sem classes utilitárias e sem empacotador (Propshaft e importmap), htmx 2 e Action Cable (as telas se atualizam por eventos do WebSocket, sem polling), PostgreSQL 19, Valkey com Sidekiq 8 para as filas, Pundit para autorização, Minitest com testes de sistema (Capybara, Cuprite e axe-core, WCAG 2.2 AA). `bin/ci` roda RuboCop, bundler-audit, Brakeman, os testes e os testes de sistema. A página pública de pagamento carrega só scripts do próprio sistema e o que o fornecedor de cartão declara (biblioteca `payment-token-efi` 3.4.1, fixada em `vendor/javascript`, sem CDN). Os segredos dos fornecedores de pagamento ficam cifrados (Active Record Encryption) com chaves em credenciais cifradas por ambiente; PDF de boleto e QR Code de Pix ficam em disco (Active Storage, sem rotas públicas) e o QR Code local usa a gem `rqrcode`. Os avisos dos fornecedores de pagamento chegam a uma rota por conta, são guardados uma vez por identificador (índice único) e processados na fila `webhooks` do Sidekiq, que consulta o fornecedor antes de mudar qualquer coisa; uma tarefa diária reprocessa os avisos que falharam e confere no fornecedor os instrumentos ativos (2.000 conferências com 200 baixas em cerca de 38 s). Tudo roda em contêineres Docker, com versões travadas. As promessas e os acordos se atualizam por eventos do WebSocket, e a tarefa diária (sidekiq-cron) quebra 3 mil promessas vencidas em cerca de 8 s e avalia 5 mil acordos em cerca de 13 s (processamento em lote, pelo Active Record); 2 mil pagamentos de parcela de acordo se confirmam em cerca de 18 s e 2 mil estornos de parcela em cerca de 28 s; um arquivo de 20 mil pagamentos com 2 mil de promessa se confirma em cerca de 145 s. O cálculo dos encargos é Ruby puro com tabelas de índices por dia (400 mil títulos recalculados em cerca de 14 s). As importações grandes são lotes em segundo plano com Active Record (nada de SQL escrito à mão para gravar): 200 mil pagamentos se conferem em cerca de 95 s e se confirmam em cerca de 23 minutos (143 linhas por segundo), e 20 mil estornos, em 12 s e 3 min 10 s (105 linhas por segundo), com a lista e o resumo respondendo em 1,1 s no meio do lote. Um milhão de acionamentos (carregados em cerca de 5 minutos por `insert_all!`): a ficha abre em 0,3 s, a lista em 0,03 s e o resumo em menos de 1 s. A tarefa diária de guarda de dados anonimiza 200 mil clientes em cerca de 100 s (10 mil em 5 s), e exportar ou anonimizar um cliente com 1.000 acionamentos leva menos de 1 s. A sessão acaba com 30 minutos sem atividade ou 8 horas. As importações são processamento em lote em segundo plano (Active Job com etapas retomáveis, Active Record e o mesmo histórico de alterações das telas): a carga de 200 mil linhas confere a mais de mil linhas por segundo e confirma a cerca de 70, sem travar as telas.

## Como rodar

Só o Docker é necessário. Na raiz do repositório:

```sh
# Imagem de desenvolvimento e ambiente (as senhas ficam num arquivo que não vai para o git).
docker build -f deploy/rails/Dockerfile.dev -t crm-rails-dev:4.0.6 deploy/rails
echo "DB_PASSWORD=$(openssl rand -hex 16)" > deploy/rails/.env.dev
cd deploy/rails
docker compose -f compose.dev.yml --env-file .env.dev up -d db valkey

# Testes completos (estilo, segurança, testes e testes de sistema).
docker compose -f compose.dev.yml --env-file .env.dev run --rm testes bin/ci
```

Para rodar a demonstração (dados fictícios, faixa de aviso, restrições e recriação diária), ligue `CRM_DEMO=1` no ambiente (modelo em `deploy/rails/env.producao.modelo`) e crie os dados sobre um banco vazio:

```sh
docker compose -f compose.dev.yml --env-file .env.dev run --rm -e CRM_DEMO=1 -e RAILS_ENV=development testes bin/rails db:prepare crm:demo_data   # cerca de 1 minuto
docker compose -f compose.dev.yml --env-file .env.dev run --rm -e CRM_DEMO=1 -e RAILS_ENV=development testes bin/rails crm:demo_reset            # apaga e recria
```

Com `CRM_DEMO=1`, o Sidekiq agenda `crm:demo_reset` para as 4h. Verificação pelo caminho do usuário, em contêiner com navegador: `deploy/rails/v5/v5.sh v5-demo.mjs http://127.0.0.1:3220`.

`deploy/rails/capturas.sh` recria as fotos desta página. A execução em produção usa `deploy/rails/compose.producao.yml` e o modelo de variáveis `deploy/rails/env.producao.modelo`.

### Credenciais cifradas em produção

Os segredos de fornecedor de pagamento (Client Secret, certificado `.p12`, segredo de webhook) são cifrados com o Active Record Encryption do Rails, e as chaves ficam nas credenciais cifradas de cada ambiente. O repositório traz só as credenciais de teste (com a chave versionada de propósito). Para produção, gere as suas: `bin/rails credentials:edit --environment production` e `bin/rails db:encryption:init` (uma lista em `primary_key` permite a rotação: `bin/rails crm:encryption:rotate`), e guarde a chave mestra (`RAILS_MASTER_KEY`) fora do repositório.

## Licença

[GNU Affero General Public License v3.0](LICENSE).

Os comentários do código citam regras (R1, R2…) e decisões das especificações. As especificações são documentos internos do projeto e não estão neste repositório; a série no blog conta cada uma.
