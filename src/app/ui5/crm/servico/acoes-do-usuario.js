// Ações sobre um vínculo (R32, R37, R40), compartilhadas pela lista de usuários e pela ficha do usuário: editar o perfil (modal pequeno),
// desativar e reativar o acesso e redefinir a senha (confirmação curta; a senha nova aparece uma vez).
sap.ui.define(["sap/m/MessageToast", "sap/m/MessageBox", "crm/servico/http", "crm/servico/formulario", "crm/servico/senha-temporaria"],
  (MessageToast, MessageBox, http, formulario, senhaTemporaria) => {
  "use strict"

  return (controlador) => {
    const texto = (chave, argumentos) => controlador.getOwnerComponent().getModel("i18n").getResourceBundle().getText(chave, argumentos)
    const concluir = (resposta) => {
      if (resposta?.mensagem) MessageToast.show(resposta.mensagem, { duration: 6000 })
      senhaTemporaria(controlador, resposta)
      controlador.carregar()
    }
    const confirmar = (titulo, mensagem, acao, perigosa, executar) => MessageBox[perigosa ? "warning" : "confirm"](mensagem, {
      title: titulo, actions: [acao, MessageBox.Action.CANCEL], emphasizedAction: acao,
      onClose: async (escolha) => {
        if (escolha !== acao) return
        try { concluir(await executar()) } catch (erro) { MessageBox.error(erro.corpo?.mensagem || erro.message) }
      }
    })

    return {
      async editarPerfil(id) {
        const dados = await http.obter(`/usuarios/${id}/perfil/edit.json`)
        formulario.abrir({
          textoCancelar: texto("acao.cancelar"), titulo: texto("usuarios.editarPerfil"), descricao: dados.descricao, escopo: "membership", url: `/usuarios/${id}/perfil`,
          metodo: "PATCH", botao: texto("usuarios.salvarPerfil"), campos: [{ nome: "profile_id", rotulo: texto("usuarios.perfilNoCredor"), tipo: "opcoes", opcoes: dados.perfis, valor: dados.perfil_id }]
        }).then(concluir)
      },
      desativar(id, nome, credor) {
        const acao = texto("usuarios.desativar")
        confirmar(texto("usuarios.desativar.pergunta"), texto("usuarios.desativar.ajuda", [nome, credor]), acao, true, () => http.excluir(`/usuarios/${id}/ativacao`))
      },
      reativar(id, nome, credor) {
        const acao = texto("usuarios.reativar")
        confirmar(texto("usuarios.reativar.pergunta"), texto("usuarios.reativar.ajuda", [nome, credor]), acao, false, () => http.enviar(`/usuarios/${id}/ativacao`, {}))
      },
      redefinirSenha(id, nome) {
        const acao = texto("usuarios.redefinirSenha")
        confirmar(texto("usuarios.redefinirSenha.pergunta"), texto("usuarios.redefinirSenha.ajuda", [nome]), acao, false, () => http.enviar(`/usuarios/${id}/redefinicao-de-senha`, {}))
      },
      async editarNome(id) {
        const dados = await http.obter(`/usuarios/${id}/nome.json`)
        formulario.abrir({
          textoCancelar: texto("acao.cancelar"), titulo: texto("usuarios.editarNome"), escopo: "user", url: `/usuarios/${id}`, metodo: "PATCH", botao: texto("acao.salvar"),
          campos: [{ nome: "name", rotulo: texto("enquadramento.nome"), tipo: "texto", obrigatorio: true, max: 150, valor: dados.nome }]
        }).then(concluir)
      }
    }
  }
})
