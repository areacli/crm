// As telas da SPA (decisão 0025, P27): o nome da rota, o padrão do hash, a view e o caminho do servidor que ela substitui. O item do menu
// cujo caminho não está aqui ainda é uma página do servidor (porte por fases): o clique navega para ela.
sap.ui.define([], () => {
  "use strict"

  // A ordem conta: o roteador fica com a primeira rota que casa, então `filas/enquadramento` vem antes de `filas/{id}`.
  // `chaveDaAba`: o que identifica a aba (a lista de clientes é uma aba só, qualquer que seja o filtro; cada ficha é a sua).
  const TELAS = [
    { rota: "resumo", padrao: "resumo", view: "crm.view.Resumo", titulo: "Resumo", caminho: /^\/resumo$/, chaveDaAba: () => ({}) },
    { rota: "clientes", padrao: "clientes:?filtro:", view: "crm.view.Clientes", titulo: "Clientes", caminho: /^\/clientes$/, chaveDaAba: () => ({}) },
    { rota: "acionamentos", padrao: "acionamentos:?filtro:", view: "crm.view.Acionamentos", titulo: "Acionamentos", caminho: /^\/acionamentos$/, chaveDaAba: () => ({}) },
    { rota: "promessasPendentes", padrao: "promessas/pendentes:?filtro:", view: "crm.view.PromessasPendentes", titulo: "Promessas pendentes", caminho: /^\/promessas\/pendentes$/, chaveDaAba: () => ({}) },
    { rota: "acordos", padrao: "acordos:?filtro:", view: "crm.view.Acordos", titulo: "Acordos", caminho: /^\/acordos$/, chaveDaAba: () => ({}) },
    { rota: "acordosPendentes", padrao: "acordos/pendentes:?filtro:", view: "crm.view.AcordosPendentes", titulo: "Acordos pendentes", caminho: /^\/acordos\/pendentes$/, chaveDaAba: () => ({}) },
    { rota: "acordo", padrao: "acordos/{id}", view: "crm.view.Acordo", titulo: "Acordo", caminho: /^\/acordos\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "simulacao", padrao: "clientes/{id}/simulacao", view: "crm.view.Simulacao", titulo: "Simular acordo", caminho: /^\/clientes\/(?<id>\d+)\/simulacao-de-acordo\/new$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "arquivoDeAcordos", padrao: "arquivo-de-acordos", view: "crm.view.ArquivoDeAcordos", titulo: "Arquivo de acordos", caminho: /^\/arquivo-de-acordos$/, chaveDaAba: () => ({}) },
    { rota: "divergencias", padrao: "divergencias-de-valor:?filtro:", view: "crm.view.Divergencias", titulo: "Divergências de valor", caminho: /^\/divergencias-de-valor$/, chaveDaAba: () => ({}) },
    { rota: "divergencia", padrao: "divergencias-de-valor/{id}", view: "crm.view.Divergencia", titulo: "Divergência", caminho: /^\/divergencias-de-valor\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "titulo", padrao: "titulos/{id}", view: "crm.view.Titulo", titulo: "Título", caminho: /^\/titulos\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "estornosAEspera", padrao: "estornos-a-espera", view: "crm.view.EstornosAEspera", titulo: "Estornos à espera", caminho: /^\/estornos-a-espera$/, chaveDaAba: () => ({}) },
    { rota: "importacoes", padrao: "importacoes:?filtro:", view: "crm.view.Importacoes", titulo: "Importações", caminho: /^\/importacoes$/, chaveDaAba: () => ({}) },
    { rota: "novaImportacao", padrao: "importacoes/nova/{tipo}", view: "crm.view.NovaImportacao", titulo: "Importar", caminho: /^\/importacoes\/nova\?kind=(?<tipo>\w+)$/, chaveDaAba: ({ tipo }) => ({ tipo }) },
    { rota: "importacao", padrao: "importacoes/{id}", view: "crm.view.Importacao", titulo: "Importação", caminho: /^\/importacoes\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "distribuicao", padrao: "distribuicao:?filtro:", view: "crm.view.Distribuicao", titulo: "Distribuição", caminho: /^\/distribuicao$/, chaveDaAba: () => ({}) },
    { rota: "novoLote", padrao: "distribuicao/lotes/novo:?filtro:", view: "crm.view.NovoLote", titulo: "Distribuir em lote", caminho: /^\/distribuicao\/lotes\/novo$/, chaveDaAba: () => ({}) },
    { rota: "lote", padrao: "distribuicao/lotes/{id}", view: "crm.view.Lote", titulo: "Lote de distribuição", caminho: /^\/distribuicao\/lotes\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "filas", padrao: "filas:?filtro:", view: "crm.view.Filas", titulo: "Filas", caminho: /^\/filas$/, chaveDaAba: () => ({}) },
    { rota: "enquadramentoDasFilas", padrao: "filas/enquadramento:?filtro:", view: "crm.view.EnquadramentoDasFilas", titulo: "Enquadramento das filas", caminho: /^\/filas\/enquadramento$/, chaveDaAba: () => ({}) },
    { rota: "conferenciaDasFilas", padrao: "filas/enquadramento/conferencia:?filtro:", view: "crm.view.ConferenciaDasFilas", titulo: "Conferir o impacto", caminho: /^\/filas\/enquadramento\/conferencia$/, chaveDaAba: () => ({}) },
    { rota: "gruposDeFilas", padrao: "filas/grupos:?filtro:", view: "crm.view.GruposDeFilas", titulo: "Grupos", caminho: /^\/filas\/grupos$/, chaveDaAba: () => ({}) },
    { rota: "fila", padrao: "filas/{id}:?filtro:", view: "crm.view.Fila", titulo: "Fila", caminho: /^\/filas\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "operacoes", padrao: "operacoes:?filtro:", view: "crm.view.Operacoes", titulo: "Operações credenciadas", caminho: /^\/operacoes$/, chaveDaAba: () => ({}) },
    { rota: "enquadramentoDaDistribuicao", padrao: "operacoes/enquadramento-da-distribuicao:?filtro:", view: "crm.view.EnquadramentoDaDistribuicao", titulo: "Enquadramento da distribuição", caminho: /^\/operacoes\/enquadramento-da-distribuicao$/, chaveDaAba: () => ({}) },
    { rota: "conferenciaDaDistribuicao", padrao: "operacoes/enquadramento-da-distribuicao/conferencia:?filtro:", view: "crm.view.ConferenciaDaDistribuicao", titulo: "Conferir o impacto", caminho: /^\/operacoes\/enquadramento-da-distribuicao\/conferencia$/, chaveDaAba: () => ({}) },
    { rota: "trilhaDasOperacoes", padrao: "operacoes/trilha:?filtro:", view: "crm.view.TrilhaDasOperacoes", titulo: "Trilha das operações", caminho: /^\/operacoes\/trilha$/, chaveDaAba: () => ({}) },
    { rota: "operacao", padrao: "operacoes/{id}", view: "crm.view.Operacao", titulo: "Operação", caminho: /^\/operacoes\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "usuarios", padrao: "usuarios:?filtro:", view: "crm.view.Usuarios", titulo: "Usuários", caminho: /^\/usuarios$/, chaveDaAba: () => ({}) },
    { rota: "usuario", padrao: "usuarios/{id}", view: "crm.view.Usuario", titulo: "Usuário", caminho: /^\/usuarios\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "perfis", padrao: "perfis:?filtro:", view: "crm.view.Perfis", titulo: "Perfis", caminho: /^\/perfis$/, chaveDaAba: () => ({}) },
    { rota: "pessoasDaOperacao", padrao: "operacao/pessoas", view: "crm.view.PessoasDaOperacao", titulo: "Pessoas da operação", caminho: /^\/operacao\/pessoas$/, chaveDaAba: () => ({}) },
    { rota: "guardaDeDados", padrao: "guarda-de-dados:?filtro:", view: "crm.view.GuardaDeDados", titulo: "Guarda de dados", caminho: /^\/guarda-de-dados$/, chaveDaAba: () => ({}) },
    { rota: "dadosDoCredor", padrao: "configuracao/dados-do-credor", view: "crm.view.DadosDoCredor", titulo: "Dados do credor", caminho: /^\/configuracao\/dados-do-credor$/, chaveDaAba: () => ({}) },
    { rota: "configuracaoDaCarteira", padrao: "configuracao/carteira", view: "crm.view.ConfiguracaoDaCarteira", titulo: "Carteira", caminho: /^\/configuracao\/carteira$/, chaveDaAba: () => ({}) },
    { rota: "metodosDeRecebimento", padrao: "configuracao/metodos-de-recebimento:?filtro:", view: "crm.view.MetodosDeRecebimento", titulo: "Métodos de recebimento", caminho: /^\/configuracao\/metodos-de-recebimento$/, chaveDaAba: () => ({}) },
    { rota: "metodoDeRecebimento", padrao: "configuracao/metodos-de-recebimento/{id}", view: "crm.view.MetodoDeRecebimento", titulo: "Método de recebimento", caminho: /^\/configuracao\/metodos-de-recebimento\/(?<id>\d+)\/editar$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "novaIntegracao", padrao: "configuracao/integracoes/nova", view: "crm.view.NovaIntegracao", titulo: "Nova integração", caminho: /^\/configuracao\/integracoes\/nova$/, chaveDaAba: () => ({}) },
    { rota: "integracao", padrao: "configuracao/integracoes/{id}", view: "crm.view.Integracao", titulo: "Integração", caminho: /^\/configuracao\/integracoes\/(?<id>\d+)\/editar$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "politicasDePagamento", padrao: "configuracao/politicas-de-pagamento", view: "crm.view.PoliticasDePagamento", titulo: "Políticas de pagamento", caminho: /^\/configuracao\/politicas-de-pagamento$/, chaveDaAba: () => ({}) },
    { rota: "glossarioDosSegmentos", padrao: "configuracao/segmentos/glossario", view: "crm.view.GlossarioDosSegmentos", titulo: "Glossário dos segmentos", caminho: /^\/configuracao\/segmentos\/glossario$/, chaveDaAba: () => ({}) },
    { rota: "novoSegmento", padrao: "configuracao/segmentos/novo:?filtro:", view: "crm.view.EditorDeSegmento", titulo: "Novo segmento", caminho: /^\/configuracao\/segmentos\/novo$/, chaveDaAba: (argumentos) => ({ tenant_id: argumentos?.["?filtro"]?.tenant_id, from: argumentos?.["?filtro"]?.from }) },
    { rota: "editarSegmento", padrao: "configuracao/segmentos/{id}/editar", view: "crm.view.EditorDeSegmento", titulo: "Editar segmento", caminho: /^\/configuracao\/segmentos\/(?<id>\d+)\/editar$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "segmento", padrao: "configuracao/segmentos/{id}", view: "crm.view.Segmento", titulo: "Segmento", caminho: /^\/configuracao\/segmentos\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "segmentos", padrao: "configuracao/segmentos:?filtro:", view: "crm.view.Segmentos", titulo: "Segmentos", caminho: /^\/configuracao\/segmentos$/, chaveDaAba: () => ({}) },
    { rota: "promessasEAcordos", padrao: "configuracao/promessas-e-acordos", view: "crm.view.PromessasEAcordos", titulo: "Promessas e acordos", caminho: /^\/configuracao\/promessas-e-acordos$/, chaveDaAba: () => ({}) },
    { rota: "indices", padrao: "configuracao/indices:?filtro:", view: "crm.view.Indices", titulo: "Índices", caminho: /^\/configuracao\/indices$/, chaveDaAba: () => ({}) },
    { rota: "resultadosDeAcionamento", padrao: "configuracao/resultados-de-acionamento", view: "crm.view.ResultadosDeAcionamento", titulo: "Resultados de acionamento", caminho: /^\/configuracao\/resultados-de-acionamento$/, chaveDaAba: () => ({}) },
    { rota: "enquadramentoFinanceiro", padrao: "configuracao/enquadramento-financeiro:?filtro:", view: "crm.view.EnquadramentoFinanceiro", titulo: "Enquadramento financeiro", caminho: /^\/configuracao\/enquadramento-financeiro$/, chaveDaAba: () => ({}) },
    { rota: "conferenciaDoEnquadramento", padrao: "configuracao/conferencias-do-enquadramento/{id}", view: "crm.view.ConferenciaDoEnquadramento", titulo: "Conferir o impacto", caminho: /^\/configuracao\/conferencias-do-enquadramento\/(?<id>[0-9a-f-]+)$/, chaveDaAba: () => ({}) },
    { rota: "cliente", padrao: "clientes/{id}:?acao:", view: "crm.view.Ficha", titulo: "Cliente", caminho: /^\/clientes\/(?<id>\d+)$/, chaveDaAba: ({ id }) => ({ id }) },
    { rota: "designSystem", padrao: "design-system", view: "crm.view.DesignSystem", titulo: "Design system", caminho: /^\/design-system$/ }
  ]

  return {
    todas: () => TELAS,
    porRota: (rota) => TELAS.find((tela) => tela.rota === rota),
    // A tela que atende um caminho do servidor (o do menu), com os parâmetros tirados dele.
    doCaminho(caminho) {
      for (const tela of TELAS) {
        const casamento = caminho.match(tela.caminho)
        if (casamento) return { tela, argumentos: { ...casamento.groups } }
      }
      return null
    }
  }
})
