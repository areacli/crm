# Ações em diálogo (decisão 0028; design system, 7.1): o link de abrir leva `data-spa-dialogo`, e o `spa/dialogos` abre a rota num diálogo preso à aba; o
# formulário vem no layout `trecho`, com o título na barra do diálogo, e o 422 refaz o corpo.
module PanelHelper
  # Link com cara de botão que abre a rota num diálogo.
  def abrir_painel(rotulo, url, variante: nil, tamanho: nil, **html)
    dados = { variant: variante, size: tamanho }.compact.merge(html.delete(:data) || {})
    link_to(rotulo, url, class: "botao", data: dados.merge(spa_dialogo: true), **html)
  end

  # Formulário do diálogo: corpo com os campos e rodapé com Cancelar e a ação. `variante`: :drawer (480 px, a altura da aba) ou :modal (400 px; `tamanho: :medio`
  # alarga para 576 px). `erro` é a mensagem do servidor; o bloco recebe o construtor do formulário. `voltar` dos chamadores antigos fica sem uso.
  def formulario_de_painel(titulo:, url:, enviar:, descricao: nil, metodo: :post, escopo: nil, variante: :drawer, tamanho: nil, perigoso: false, erro: nil, voltar: nil, cancelar: "Cancelar", &campos) # rubocop:disable Lint/UnusedMethodArgument
    content_for :title, titulo
    formulario_da_spa(titulo:, url:, enviar:, descricao:, metodo:, escopo:, variante:, tamanho:, perigoso:, erro:, cancelar:, &campos)
  end

  # Confirmação curta de uma ação destrutiva ou sem dados (modal pequeno): o botão abre `/confirmacao/<token>`, onde o token é assinado e leva o título, a mensagem
  # e o destino do envio (nada que o navegador escolha). A autorização continua na ação de destino.
  def confirmar_no_painel(rotulo, titulo:, mensagem:, acao:, url:, metodo: :post, perigoso: true, variante: (perigoso ? "danger-outline" : "secondary"), tamanho: nil, **html)
    carga = { titulo: titulo, mensagem: mensagem, acao: acao, url: url, metodo: metodo, perigoso: perigoso }
    token = Confirmation.sign(carga)
    abrir_painel rotulo, confirmation_path(token), variante: variante, tamanho: tamanho, **html
  end
end
