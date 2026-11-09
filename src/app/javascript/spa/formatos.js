// Formatters das grades (plano, seção 6): o `datagrid` não escapa o valor da célula, e o nome de um cliente vem de planilha importada. Toda coluna passa por aqui.
export const esc = (valor) => String(valor ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))

const selo = ({ texto, tom }) => `<span class="situacao" data-tone="${esc(tom)}">${esc(texto)}</span>`

const rico = (valor) => {
  if (valor === null || typeof valor !== "object") return esc(valor)
  const texto = valor.href ? `<a href="${esc(valor.href)}">${esc(valor.texto)}</a>` : esc(valor.texto)
  return [texto, ...(valor.selos || []).map(selo)].join(" ")
}

const acoes = (lista) => {
  if (!lista?.length) return ""
  const itens = lista.map(({ texto, href, dialogo }) => `<a class="botao" href="${esc(href)}"${dialogo ? " data-spa-dialogo" : ""}>${esc(texto)}</a>`).join("")
  return `<button type="button" class="menu-de-linha" data-spa-popover aria-label="Ações">⋯</button><div popover="auto" class="menu">${itens}</div>`
}

// `html`: só para a célula de tabela que o Rails escreveu (`transformarTabela`), já escapada pelo ERB. Valor vindo de JSON nunca usa este.
const html = (valor) => valor ?? ""

export const FORMATTERS = { html, texto: esc, numero: esc, rico, selos: (lista) => (lista || []).map(selo).join(" "), acoes }
