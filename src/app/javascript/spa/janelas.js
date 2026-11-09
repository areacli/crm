// Janelas de detalhe (padrões de interface, revisão 38): presas à aba de origem, somem ao trocar de aba e voltam com ela. Dá para abrir várias; abrir de novo traz a janela para a frente.
import { esc } from "spa/formatos"
import { carregar, tituloDe } from "spa/trecho"

const $ = window.jQuery

// Refaz o conteúdo da janela (depois de gravar algo dentro dela).
export function recarregar(corpo) {
  carregar(corpo, corpo.data("url"))
  $(document).trigger("spa:janela-gravou", [corpo.data("url")])
}

export function abrir(url, reg) {
  const aberta = reg.janelas.get(url)
  if (aberta) {
    aberta.window("open").window("window").css("z-index", $.fn.window.defaults.zIndex++)
    return
  }
  const corpo = $('<div class="janela-corpo"></div>').appendTo(reg.raiz)
  const deslocamento = reg.janelas.size
  corpo.window({
    title: "Carregando…", inline: true, constrain: true, width: 720, height: Math.min(560, reg.raiz.height() - 100),
    left: 300 + deslocamento * 34, top: 84 + deslocamento * 30, collapsible: false, minimizable: false, modal: false, shadow: false,
    onClose() { reg.janelas.delete(url); $(this).window("destroy") },
  })
  reg.janelas.set(url, corpo)
  corpo.data("url", url)
  // Na falha, o título não fica em "Carregando…": diz que não abriu (o registro de fora da operação responde como não encontrado).
  carregar(corpo, url, { depois: () => corpo.window("setTitle", esc(tituloDe(corpo))) })
    .fail((xhr, estado) => { if (estado !== "abort") corpo.window("setTitle", xhr.status === 404 ? "Não encontrado" : "Não foi possível abrir") })
}
