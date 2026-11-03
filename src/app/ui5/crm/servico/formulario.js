// Formulário de uma ação (regra de ação, padrões de interface revisão 33): 1 ou 2 campos num `Dialog` pequeno; formulário médio numa página
// para o painel lateral da aba (`emPainel`, que recebe a página). Envia às rotas de sempre do Rails, no escopo de parâmetros da ação; a recusa
// (422) volta como mensagem dentro do formulário, sem fechar.
// Campo: { nome, rotulo, tipo: "texto" | "textoLongo" | "data" | "dataEHora" | "valor" | "numero" | "opcoes" | "varios" | "marca" | "oculto" | "grupo", valor,
// opcoes: [{ id, nome }], obrigatorio, ajuda, max, dependeDe, opcoesPor }. "varios" escolhe vários da lista (valor: os ids); "marcas" faz o mesmo com uma
// caixa por opção; "grupo" é só o título de um grupo de campos. Com `dependeDe` (o nome de outro campo "opcoes"), as opções vêm de `opcoesPor[valor dele]`. O nome com
// ponto vai aninhado ("queue_positions.12" vira { queue_positions: { 12: ... } }). Um `aviso` no topo diz uma consequência antes de enviar.
sap.ui.define([
  "sap/m/Dialog", "sap/m/Page", "sap/m/Button", "sap/m/Label", "sap/m/Input", "sap/m/DatePicker", "sap/m/Select", "sap/ui/core/Item", "sap/m/Text",
  "sap/m/MessageStrip", "sap/m/VBox", "sap/m/OverflowToolbar", "sap/m/ToolbarSpacer", "sap/m/CheckBox", "sap/m/DateTimePicker", "sap/m/TextArea", "sap/m/MultiComboBox", "sap/m/Title", "crm/servico/http"
], (Dialog, Page, Button, Label, Input, DatePicker, Select, Item, Text, MessageStrip, VBox, OverflowToolbar, ToolbarSpacer, CheckBox, DateTimePicker, TextArea, MultiComboBox, Title, http) => {
  "use strict"

  function controle(campo) {
    switch (campo.tipo) {
      case "data": return new DatePicker({ value: campo.valor || "", valueFormat: "yyyy-MM-dd", displayFormat: "dd/MM/yyyy", required: campo.obrigatorio })
      case "opcoes": return new Select({ width: "100%", selectedKey: campo.valor || "", forceSelection: !campo.vazio, items: (campo.opcoes || []).map((opcao) => new Item({ key: opcao.id, text: opcao.nome })) })
      case "valor": return new Input({ value: campo.valor || "", inputMode: "Decimal", required: campo.obrigatorio })
      case "numero": return new Input({ value: campo.valor ?? "", type: "Number", required: campo.obrigatorio })
      case "dataEHora": return new DateTimePicker({ value: campo.valor || "", valueFormat: "yyyy-MM-ddTHH:mm", displayFormat: "dd/MM/yyyy HH:mm", required: campo.obrigatorio })
      case "textoLongo": return new TextArea({ value: campo.valor || "", rows: 4, width: "100%", maxLength: campo.max || 2000, required: campo.obrigatorio })
      case "marca": return new CheckBox({ text: campo.rotulo, selected: Boolean(campo.valor) })
      case "marcas": return new VBox({ renderType: "Bare", items: (campo.opcoes || []).map((opcao) => new CheckBox({ text: opcao.nome, selected: (campo.valor || []).includes(opcao.id) }).data("id", opcao.id)) })
      case "varios": return new MultiComboBox({ width: "100%", selectedKeys: campo.valor || [], items: (campo.opcoes || []).map((opcao) => new Item({ key: opcao.id, text: opcao.nome })) })
      default: return new Input({ value: campo.valor || "", maxLength: campo.max || 300, required: campo.obrigatorio })
    }
  }

  function valorDe(campo, entrada) {
    if (campo.tipo === "oculto") return campo.valor
    if (campo.tipo === "opcoes") return entrada.getSelectedKey()
    if (campo.tipo === "marca") return entrada.getSelected() ? "1" : "0"
    if (campo.tipo === "varios") return entrada.getSelectedKeys()
    if (campo.tipo === "marcas") return entrada.getItems().filter((caixa) => caixa.getSelected()).map((caixa) => caixa.data("id"))
    return entrada.getValue()
  }

  return {
    // Abre o formulário. Devolve uma promessa resolvida com a resposta do servidor quando a ação dá certo.
    abrir({ titulo, descricao, aviso, campos, escopo, url, metodo = "POST", botao, perigoso = false, emPainel, largura = "25rem", textoCancelar = "Cancelar" }) {
      return new Promise((resolver) => {
        const mensagem = new MessageStrip({ type: "Error", showIcon: true, visible: false })
        const entradas = []
        const conteudo = new VBox({ renderType: "Bare", items: [mensagem] }).addStyleClass("sapUiSmallMargin")
        if (aviso) conteudo.insertItem(new MessageStrip({ text: aviso, type: "Warning", showIcon: true }).addStyleClass("sapUiSmallMarginBottom"), 0)
        if (descricao) conteudo.insertItem(new Text({ text: descricao }).addStyleClass("nota sapUiSmallMarginBottom"), 0)
        campos.filter((campo) => campo.tipo !== "oculto").forEach((campo) => {
          if (campo.tipo === "grupo") return conteudo.addItem(new Title({ text: campo.rotulo, level: "H3" }).addStyleClass("sapUiSmallMarginTop"))
          const entrada = controle(campo)
          entradas.push([campo, entrada])
          // A marca já tem o texto ao lado da caixa; os outros campos ganham o rótulo acima.
          if (campo.tipo !== "marca") conteudo.addItem(new Label({ text: campo.rotulo, required: campo.obrigatorio, labelFor: entrada }).addStyleClass("sapUiSmallMarginTop"))
          conteudo.addItem(entrada)
          if (campo.ajuda) conteudo.addItem(new Text({ text: campo.ajuda }).addStyleClass("nota"))
        })

        // Lista que depende de outra: troca as opções quando a outra muda.
        entradas.filter(([campo]) => campo.dependeDe).forEach(([campo, entrada]) => {
          entradas.find(([outro]) => outro.nome === campo.dependeDe)?.[1].attachChange((evento) => {
            entrada.removeAllItems()
            ;(campo.opcoesPor[evento.getSource().getSelectedKey()] || []).forEach((opcao) => entrada.addItem(new Item({ key: opcao.id, text: opcao.nome })))
          })
        })

        let fechar
        const enviar = new Button({ text: botao, type: perigoso ? "Reject" : "Emphasized", press: async () => {
          const dados = {}
          campos.filter((campo) => campo.tipo !== "grupo").forEach((campo) => {
            const valor = campo.tipo === "oculto" ? campo.valor : valorDe(campo, entradas.find(([c]) => c === campo)[1])
            const chaves = campo.nome.split(".")
            const ultima = chaves.pop()
            chaves.reduce((objeto, chave) => (objeto[chave] ||= {}), dados)[ultima] = valor
          })
          enviar.setBusy(true)
          try {
            const resposta = await http[metodo === "PATCH" ? "alterar" : metodo === "DELETE" ? "excluir" : "enviar"](url, { [escopo]: dados })
            fechar()
            resolver(resposta || {})
          } catch (erro) {
            mensagem.setText(erro.corpo?.mensagem || erro.message).setVisible(true)
          } finally {
            enviar.setBusy(false)
          }
        } })
        const cancelar = new Button({ text: textoCancelar, press: () => fechar() })

        if (emPainel) {
          const pagina = new Page({ title: titulo, content: [conteudo], footer: new OverflowToolbar({ content: [new ToolbarSpacer(), cancelar, enviar] }) }).addStyleClass("painel")
          fechar = () => { emPainel.fechar(pagina); setTimeout(() => pagina.destroy()) }
          emPainel.mostrar(pagina)
        } else {
          const dialogo = new Dialog({ title: titulo, contentWidth: largura, content: [conteudo], beginButton: enviar, endButton: cancelar, afterClose: () => dialogo.destroy() })
          fechar = () => dialogo.close()
          dialogo.open()
        }
        entradas[0]?.[1].focus?.()
      })
    }
  }
})
