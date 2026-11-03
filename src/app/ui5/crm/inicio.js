// Início da SPA (decisão 0025): lê a configuração que a casca entregou e monta o componente do CRM no corpo da página.
sap.ui.define(["sap/ui/core/ComponentContainer"], (ComponentContainer) => {
  "use strict"

  const configuracao = JSON.parse(document.getElementById("configuracao-da-casca").textContent)
  new ComponentContainer({
    name: "crm", manifest: true, async: true, height: "100%",
    settings: { componentData: { configuracao } }
  }).placeAt("conteudo")
})
