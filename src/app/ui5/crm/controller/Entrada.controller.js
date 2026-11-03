// Entrada (02; decisão 0025): manda e-mail e senha ao Rails e, aceito, troca para a casca. A mensagem de recusa é a do servidor, a mesma
// para usuário inexistente, senha errada e bloqueio (não revela quem existe).
sap.ui.define(["sap/ui/core/mvc/Controller", "crm/servico/http"], (Controller, http) => {
  "use strict"

  return Controller.extend("crm.controller.Entrada", {
    async entrar() {
      const botao = this.byId("entrar")
      botao.setBusy(true)
      try {
        const resposta = await http.enviar("/session", { email_address: this.byId("email").getValue(), password: this.byId("senha").getValue() })
        this.byId("senha").setValue("")
        this.byId("mensagem").setVisible(false)
        // Enquanto houver telas fora da SPA, a volta para a página do servidor que pediu a entrada recarrega a página.
        if (resposta.destino && resposta.destino !== "/") return window.location.assign(resposta.destino)
        const sessao = this.getOwnerComponent().getModel("sessao")
        sessao.setProperty("/usuario", resposta.usuario)
        sessao.setProperty("/aviso", resposta.aviso)
        this.getOwnerComponent().mostrarTela()
      } catch (erro) {
        this.byId("senha").setValue("")
        this.byId("mensagem").setText(erro.corpo?.mensagem || erro.message).setVisible(true)
        this.byId("email").focus()
      } finally {
        botao.setBusy(false)
      }
    },

    // Na demonstração, escolher um usuário preenche o formulário.
    preencher(evento) {
      const usuario = evento.getSource().getBindingContext("sessao").getObject()
      this.byId("email").setValue(usuario.email)
      this.byId("senha").setValue(usuario.senha)
      this.byId("entrar").focus()
    }
  })
})
