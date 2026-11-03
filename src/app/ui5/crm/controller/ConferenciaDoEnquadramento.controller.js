// Conferência do impacto do enquadramento financeiro (13, R272, R284, R291): o JSON da mesma rota (/configuracao/conferencias-do-enquadramento/<id>);
// enquanto confere, espera o fim pelo recurso `credores` do tempo real. Confirmar aplica na hora e volta ao enquadramento; "Voltar e editar" volta ao
// formulário de onde a mudança saiu; descartar só volta. A conferência expirada é recusada pelo servidor, com a mensagem.
sap.ui.define(["sap/ui/core/mvc/Controller", "sap/ui/model/json/JSONModel", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/tempo-real",
  "crm/servico/telas"], (Controller, JSONModel, MessageToast, MessageBox, http, tempoReal, telas) => {
  "use strict"

  const vazio = () => ({ conferindo: true, falhou: false, pronto: false, resumo: "", erro: "", alteracoes: [], itens: [], movimentos: [], tem_valores: false,
    valores: [], avisos: [] })

  return Controller.extend("crm.controller.ConferenciaDoEnquadramento", {
    onInit() {
      const { argumentos } = this.getView().getViewData()
      this.id = argumentos.id
      this.getView().setModel(new JSONModel(vazio()), "dados")
      this.desligar = [
        tempoReal.ouvir("credores", () => { if (this.getView().getModel("dados").getProperty("/conferindo")) this.carregar() }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
      this.carregar()
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    // Uma aba só para a conferência: outra mudança troca a conferência mostrada.
    mudarArgumentos(argumentos) {
      if (!argumentos?.id || argumentos.id === this.id) return
      this.id = argumentos.id
      this.getView().getModel("dados").setData(vazio())
      this.carregar()
    },

    async carregar() {
      try {
        this.getView().getModel("dados").setData({ ...vazio(), ...(await http.obter(`/configuracao/conferencias-do-enquadramento/${encodeURIComponent(this.id)}.json`)) })
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message, { onClose: () => this.voltar() })
      }
    },

    voltar(filtro = {}) {
      const credor = this.getView().getModel("dados").getProperty("/credor_id")
      this.getOwnerComponent().getRouter().navTo("enquadramentoFinanceiro", { "?filtro": { ...(credor ? { tenant_id: credor } : {}), ...filtro } })
    },

    async confirmar() {
      const dados = this.getView().getModel("dados").getData()
      try {
        const resposta = await http.enviar("/configuracao/confirmacao-do-enquadramento", { tenant_id: dados.credor_id, confirmation: { token: dados.token } })
        MessageToast.show(resposta.mensagem, { duration: 6000 })
        this.voltar()
        this.getView().getViewData()?.fechar?.()
      } catch (erro) {
        // Conferência velha ou expirada (R284): a mensagem e de volta ao enquadramento, como na página do servidor.
        MessageBox.error(erro.corpo?.mensagem || erro.message, { onClose: () => this.voltar() })
      }
    },

    // De onde a mudança saiu: as regras de um item abrem no painel do enquadramento; outra tela da SPA, se houver; senão, a página do servidor.
    voltarEEditar() {
      const destino = this.getView().getModel("dados").getProperty("/voltar") || ""
      if (destino === "/configuracao/enquadramento-financeiro") return this.voltar()
      const regras = destino.match(/^\/configuracao\/enquadramento-financeiro\/(\d+)\/regras$/)
      if (regras) return this.voltar({ editar: regras[1] })
      const tela = telas.doCaminho(destino)
      if (tela) return this.getOwnerComponent().getRouter().navTo(tela.tela.rota, tela.argumentos)
      window.location.assign(destino)
    },

    descartar() {
      this.voltar()
      this.getView().getViewData()?.fechar?.()
    }
  })
})
