// Segmentos (13, R252, R273, R295): a lista da mesma rota, um cartão por credor. Criar, editar e duplicar abrem o editor numa aba; desativar e
// reativar valem na hora, ou levam à conferência do impacto quando o segmento é usado no enquadramento; excluir só o sem uso, com confirmação curta.
// Tempo real pelo recurso `credores` (o recálculo e as mudanças do credor).
sap.ui.define(["crm/controller/Lista", "sap/m/Menu", "sap/m/MenuItem", "sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/tempo-real",
  "crm/controller/SegmentosDestino"],
  (Lista, Menu, MenuItem, MessageToast, MessageBox, http, tempoReal, destino) => {
  "use strict"

  return Lista.extend("crm.controller.Segmentos", {
    endereco: "/configuracao/segmentos",
    filtroInicial: { busca: "", seleciona: "", uso: "", situacao: "" },

    onInit() {
      Lista.prototype.onInit.apply(this, arguments)
      const credores = () => (this.getView().getModel("dados").getProperty("/credores") || []).map((credor) => credor.id)
      this.desligar = [
        tempoReal.ouvir("credores", (mensagem) => {
          if (mensagem.acao !== "atualizar" || (mensagem.registros || []).some((credor) => credores().includes(String(credor.id)))) this.carregar()
        }),
        tempoReal.ouvir("*conectado", () => this.carregar())
      ]
    },

    onExit() {
      this.desligar?.forEach((desligar) => desligar())
    },

    texto(chave, argumentos) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    },

    // A busca por nome espera uma pausa curta na digitação, como as outras listas.
    buscarAoDigitar(evento) {
      clearTimeout(this.espera)
      this.getView().getModel("filtro").setProperty("/busca", evento.getParameter("newValue"))
      this.espera = setTimeout(() => this.buscar(), 300)
    },

    // O credor do cartão da linha (o caminho do segmento é /credores/N/segmentos/M).
    credorDaLinha(contexto) {
      return this.getView().getModel("dados").getProperty(contexto.getPath().split("/segmentos/")[0])
    },

    abrirGlossario() {
      this.navegar("glossarioDosSegmentos", {})
    },

    criar(evento) {
      const credor = evento.getSource().getBindingContext("dados").getObject()
      this.navegar("novoSegmento", { "?filtro": { tenant_id: credor.id } })
    },

    abrirDaLinha(evento) {
      this.navegar("segmento", { id: this.objetoDaLinha(evento).id })
    },

    mostrarLeitura(evento) {
      const segmento = this.objetoDaLinha(evento)
      MessageBox.information(segmento.leitura || segmento.condicoes, { title: this.texto("segmentos.leitura", [segmento.nome]) })
    },

    concluir(resposta) {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      if (!destino.seguir(this, resposta)) this.carregar()
    },

    async executar(metodo, url) {
      try {
        this.concluir(await http[metodo](url, metodo === "excluir" ? undefined : {}))
      } catch (erro) {
        MessageBox.error(erro.corpo?.mensagem || erro.message)
      }
    },

    excluir(segmento) {
      const acao = this.texto("acao.excluir")
      MessageBox.warning(segmento.mensagem_de_excluir, {
        title: this.texto("segmentos.excluir.pergunta"), actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
        onClose: (escolha) => { if (escolha === acao) this.executar("excluir", `/configuracao/segmentos/${segmento.id}`) }
      })
    },

    acoes(evento) {
      const contexto = evento.getSource().getBindingContext("dados")
      const segmento = contexto.getObject()
      const credor = this.credorDaLinha(contexto)
      const itens = [new MenuItem({ text: this.texto("segmentos.abrir"), press: () => this.navegar("segmento", { id: segmento.id }) })]
      if (credor.pode_mudar) {
        itens.push(new MenuItem({ text: this.texto("acao.editar"), press: () => this.navegar("editarSegmento", { id: segmento.id }) }))
        itens.push(new MenuItem({ text: this.texto("segmentos.duplicar"), press: () => this.navegar("novoSegmento", { "?filtro": { tenant_id: credor.id, from: segmento.id } }) }))
        itens.push(segmento.ativo
          ? new MenuItem({ text: this.texto("segmentos.desativar"), press: () => this.executar("excluir", `/configuracao/segmentos/${segmento.id}/ativacao`) })
          : new MenuItem({ text: this.texto("segmentos.reativar"), press: () => this.executar("enviar", `/configuracao/segmentos/${segmento.id}/ativacao`) }))
        if (!segmento.em_uso) itens.push(new MenuItem({ text: this.texto("acao.excluir"), press: () => this.excluir(segmento) }))
      }
      const menu = new Menu({ closed: () => setTimeout(() => menu.destroy()), items: itens })
      this.getView().addDependent(menu)
      menu.openBy(evento.getSource())
    }
  })
})
