// Painel lateral da aba (regra de ação, padrões de interface revisão 33): o formulário médio vai à segunda coluna do `FlexibleColumnLayout` da tela
// e volta a uma coluna ao fechar. O modelo `ui` da tela ganha `/painelAberto`, para o que precisa sair do caminho enquanto o painel está aberto.
sap.ui.define([], () => {
  "use strict"

  return (colunas, ui) => ({
    mostrar(pagina) {
      colunas.addMidColumnPage(pagina)
      colunas.toMidColumnPage(pagina)
      colunas.setLayout("TwoColumnsBeginExpanded")
      ui?.setProperty("/painelAberto", true)
    },
    fechar(pagina) {
      colunas.removeMidColumnPage(pagina)
      colunas.setLayout("OneColumn")
      ui?.setProperty("/painelAberto", false)
    }
  })
})
