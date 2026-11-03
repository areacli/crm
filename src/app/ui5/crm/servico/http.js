// Pedidos JSON ao Rails (decisão 0025): o token CSRF da casca em todo pedido que muda dado, a resposta em JSON. Erro vira exceção com o
// estado e o corpo, para a tela mostrar a mensagem ou marcar os campos (422).
sap.ui.define([], () => {
  "use strict"

  const token = () => document.querySelector("meta[name=csrf-token]")?.content

  class ErroHttp extends Error {
    constructor(status, corpo) {
      super(corpo?.mensagem || `HTTP ${status}`)
      this.status = status
      this.corpo = corpo || {}
    }
  }

  async function pedir(metodo, url, dados) {
    const resposta = await fetch(url, {
      method: metodo,
      credentials: "same-origin",
      headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": token() },
      body: dados === undefined ? undefined : JSON.stringify(dados)
    })
    const texto = await resposta.text()
    const corpo = texto ? JSON.parse(texto) : null
    if (!resposta.ok) throw new ErroHttp(resposta.status, corpo)
    return corpo
  }

  return {
    ErroHttp,
    obter: (url) => pedir("GET", url),
    enviar: (url, dados) => pedir("POST", url, dados),
    alterar: (url, dados) => pedir("PATCH", url, dados),
    excluir: (url, dados) => pedir("DELETE", url, dados),
    // Envio de arquivo (importações): o formulário multipart, com o mesmo token e a mesma leitura da resposta.
    async enviarFormulario(url, formulario) {
      const resposta = await fetch(url, { method: "POST", credentials: "same-origin", headers: { Accept: "application/json", "X-CSRF-Token": token() }, body: formulario })
      const texto = await resposta.text()
      const corpo = texto ? JSON.parse(texto) : null
      if (!resposta.ok) throw new ErroHttp(resposta.status, corpo)
      return corpo
    }
  }
})
