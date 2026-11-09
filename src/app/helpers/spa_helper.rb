# Marcação da SPA em EasyUI (decisão 0028). Nenhuma view escreve classe `easyui-` nem chama plugin: as views usam estes helpers, e os módulos `spa/` montam os componentes.
module SpaHelper
  # Canais do tempo real que a tela pede (`content_for :cable_channels`, em JSON), para a aba assinar.
  def canais_do_trecho = JSON.parse(CGI.unescapeHTML(content_for(:cable_channels).to_s).presence || "[]")

  # Grade (`datagrid`). `url`: lista paginada no servidor, em `{ total, rows }`. `linhas`: tabela da própria tela, sem paginar. `colunas`: `{ campo:, titulo:, largura:, tipo:, ordena: }`;
  # `tipo` é `texto` (o padrão), `numero`, `rico` (`{ texto:, href:, selos: [] }`), `selos` ou `acoes`. Todo tipo passa pelo formatter comum, que escapa o texto.
  def grade(colunas:, url: nil, linhas: nil, vazio: "Nada encontrado.", ordem: nil, direcao: "desc")
    tag.div(class: "grade") do
      tag.table(data: { grade: { colunas: colunas, url: url, linhas: linhas, vazio: vazio, ordem: ordem, direcao: direcao }.compact })
    end
  end

  # Abas internas (ficha): cada uma carrega o próprio trecho ao ser escolhida. `itens` são `[rótulo, caminho, contagem, atual?]`, como em `abas_da_pagina`.
  def abas_internas(itens)
    tag.div(class: "abas-internas", data: { abas: itens.map { |texto, caminho, contagem, atual| { titulo: texto, caminho: caminho, contagem: contagem, atual: atual } } })
  end

  # Valor editável na própria tela (design system, 7.1): o texto e o "Editar"; o `spa/inline` abre o campo sob pedido e grava com `X-CRM-Inline`, e o controlador
  # responde com `inline_finish` ou `inline_refuse`. Sem permissão, use só o texto. `botao: false`: o "Editar" fica no menu da linha (`editar_na_linha`).
  # `opcoes` (`[[texto, valor], ...]`) e `selecionado`: a edição abre uma lista de escolha em vez do campo de texto (o perfil do usuário).
  def campo_inline(valor, rotulo:, url:, nome:, metodo: :patch, maximo: 200, botao: true, opcoes: nil, selecionado: nil)
    dados = { url: url, nome: nome, metodo: metodo, rotulo: rotulo, maximo: maximo, opcoes: opcoes, selecionado: (selecionado&.to_s) }.compact
    tag.span(class: "inline", data: { inline: dados }) do
      editar = tag.button("Editar", type: "button", data: { variant: "link", size: "small", inline_editar: true }, "aria-label": "Editar #{rotulo.downcase}") if botao
      safe_join([ tag.span(valor, class: "inline-valor"), editar ].compact, " ")
    end
  end

  # Item "Editar" do menu da linha: abre o `campo_inline` da mesma linha.
  def editar_na_linha = tag.button("Editar", type: "button", class: "botao", data: { inline_abrir: true })

  # Item "Editar" do menu da linha para registro com vários campos (endereço): o formulário de `url` abre no detalhe da própria linha (design system, 7.1).
  def editar_no_detalhe(url) = link_to("Editar", url, class: "botao", data: { spa_no_detalhe: true })

  # Formulário com cálculo à vista (design system, 7.2): o resultado vem de `url` a cada mudança e entra no elemento `resultado_do_calculo`.
  def calculo_a_vista(url) = { data: { calculo: url } }

  # Valor em reais com controle deslizante ao lado do campo (design system, revisão 22): arrastar é rápido, digitar acerta o centavo. `auto`: [nome, valor] do campo escondido
  # que diz que a pessoa ainda não mexeu nele. `unidade`: "reais" ou "percentual"; as duas em centésimos na faixa. `spa/deslizantes` monta o controle e recebe os limites novos a cada cálculo.
  def valor_com_deslizante(nome, valor, id:, minimo: 0, maximo: 0, descrito_por: nil, auto: nil, unidade: "reais")
    tag.div(class: "valor-com-deslizante", data: { spa_deslizante: true, minimo: minimo.to_i, maximo: maximo.to_i, unidade: unidade }) do
      safe_join([ tag.div(class: "trilho-do-deslizante"), text_field_tag(nome, valor, id: id, inputmode: "decimal", autocomplete: "off", "aria-describedby": descrito_por),
                  (hidden_field_tag(auto.first, auto.last, id: nil, data: { deslizante_auto: true }) if auto) ].compact)
    end
  end

  # Opções de um filtro que vai ao endereço: o valor sai em português (`FilterValue`); o selecionado é o que veio no próprio endereço.
  def opcoes_de_filtro(pares, selecionado)
    options_for_select(pares.map { |rotulo, valor| [ rotulo, FilterValue.to_url(valor) ] }, selecionado)
  end

  def resultado_do_calculo(&) = tag.div(capture(&), class: "resultado-do-calculo", data: { resultado_do_calculo: true })

  # Formulário no diálogo preso à aba: o título vai para a barra do diálogo, e o `spa/dialogos` envia por `$.ajax` (422 refaz o corpo; 204 fecha).
  def formulario_da_spa(titulo:, url:, enviar:, descricao:, metodo:, escopo:, variante:, tamanho:, perigoso:, erro:, cancelar: "Cancelar", &campos)
    largura = variante.to_s == "modal" ? (tamanho.to_s == "medio" ? 576 : 400) : 480
    form_with(url: url, method: metodo, scope: escopo, class: "dialogo", data: { titulo: titulo, largura_do_dialogo: largura, altura_da_aba: (variante.to_s == "modal" ? nil : true) }.compact) do |form|
      corpo = tag.div(safe_join([ (tag.p(descricao, class: "descricao") if descricao), (aviso(tom: :danger) { tag.p erro } if erro), (capture(form, &campos) if campos) ].compact), class: "dialogo-corpo")
      fechar = tag.button(cancelar, type: "button", data: { variant: "secondary", spa_fechar: true })
      rodape = tag.footer(safe_join([ fechar, (tag.button(enviar, type: "submit", data: { variant: (perigoso ? "danger" : nil) }.compact) if enviar) ].compact))
      safe_join([ corpo, rodape ])
    end
  end
end
