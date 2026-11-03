// Campos do método de recebimento (16, R373), compartilhados pela criação (painel da lista) e pela página do método.
sap.ui.define([], () => {
  "use strict"

  return (texto, metodo) => [
    { nome: "kind", rotulo: texto("importacoes.tipo"), tipo: "opcoes", opcoes: metodo.tipos, valor: metodo.tipo },
    metodo.codigo_travado
      ? { nome: "code", tipo: "oculto", valor: metodo.codigo }
      : { nome: "code", rotulo: texto("metodos.codigo"), tipo: "texto", obrigatorio: true, max: 100, valor: metodo.codigo, ajuda: texto("metodos.codigo.ajuda") },
    { nome: "description", rotulo: texto("metodos.descricao"), tipo: "texto", obrigatorio: true, max: 200, valor: metodo.descricao }
  ]
})
