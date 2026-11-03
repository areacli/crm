// Sair (decisão 0025): encerra a sessão no servidor e volta à entrada. As abas abertas desta janela são esquecidas.
sap.ui.define(["crm/servico/http"], (http) => {
  "use strict"

  return {
    async sair(componente) {
      await http.excluir("/session")
      sessionStorage.removeItem("crm.abas")
      // A página recarrega: o token CSRF muda com a sessão nova, e nada da sessão anterior fica na memória.
      window.location.assign("/")
    }
  }
})
