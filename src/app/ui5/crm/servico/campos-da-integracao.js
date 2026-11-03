// Campos do manifesto do fornecedor (12, R261), para a página e a criação da integração: monta os controles num SimpleForm e lê os valores num FormData,
// nos grupos que o servidor espera (config, secrets, files). Segredo e arquivo vão em branco e só seguem quando preenchidos.
sap.ui.define(["sap/m/Label", "sap/m/Input", "sap/m/Select", "sap/ui/core/Item", "sap/m/Text", "sap/ui/unified/FileUploader", "sap/m/VBox"],
  (Label, Input, Select, Item, Text, FileUploader, VBox) => {
  "use strict"

  function controle(campo) {
    switch (campo.tipo) {
      case "number": return new Input({ value: campo.valor, type: "Number", required: campo.obrigatorio })
      case "select": return new Select({ width: "100%", selectedKey: campo.valor, items: (campo.opcoes || []).map((opcao) => new Item({ key: opcao.id, text: opcao.nome })) })
      case "secret": return new Input({ value: "", type: "Password", required: campo.obrigatorio })
      case "file": return new FileUploader({ width: "100%", required: campo.obrigatorio, fileType: ["p12", "pfx"], change: (evento) => { campo.arquivo = evento.getParameter("files")?.[0] } })
      default: return new Input({ value: campo.valor, maxLength: campo.max || 0, required: campo.obrigatorio })
    }
  }

  return {
    // Põe no formulário um rótulo, o controle e a ajuda de cada campo; devolve a lista [campo, controle].
    montar(formulario, campos) {
      formulario.destroyContent()
      return campos.map((campo) => {
        const entrada = controle(campo)
        formulario.addContent(new Label({ text: campo.rotulo, required: campo.obrigatorio, labelFor: entrada }))
        const bloco = new VBox({ renderType: "Bare", items: [entrada] })
        if (campo.ajuda) bloco.addItem(new Text({ text: campo.ajuda }).addStyleClass("nota"))
        ;(campo.certificado || []).forEach((par) => bloco.addItem(new Text({ text: `${par.rotulo}: ${par.valor}` }).addStyleClass("nota")))
        formulario.addContent(bloco)
        return [campo, entrada]
      })
    },

    // Acrescenta os valores ao FormData no escopo `payment_account`.
    preencher(dados, entradas) {
      entradas.forEach(([campo, entrada]) => {
        const nome = `payment_account[${campo.grupo}][${campo.nome}]`
        if (campo.tipo === "file") {
          if (campo.arquivo) dados.append(nome, campo.arquivo)
        } else if (campo.tipo === "select") {
          dados.append(nome, entrada.getSelectedKey())
        } else if (campo.tipo !== "secret" || entrada.getValue()) {
          dados.append(nome, entrada.getValue())
        }
      })
    }
  }
})
