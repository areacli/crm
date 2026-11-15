# Valores de filtro no endereço (padrões de interface, revisão 39): o código de um estado ou de um tipo é interno, em inglês, como as colunas; no endereço ele sai em português.
# Quem monta o filtro chama `to_url`, e quem lê chama `from_url`, cada um no seu lugar.
module FilterValue
  VALUES = {
    "portfolio" => "carteira", "payments" => "pagamentos", "reversals" => "estornos",
    "spoke_with_customer" => "falou_com_o_cliente", "spoke_with_third_party" => "falou_com_terceiro", "no_contact" => "sem_contato",
    "record_opened" => "registro_aberto", "search" => "busca", "not_found" => "nao_encontrado", "export" => "exportacao",
    "pending" => "pendente", "approved" => "aprovado", "refused" => "recusado", "not_approved" => "nao_aprovado", "expired" => "vencido", "canceled" => "cancelado",
    "awaiting_effectuation" => "aguardando_efetivacao", "active_on_time" => "ativo_em_dia", "active_late" => "ativo_em_atraso", "settled" => "quitado", "broken" => "quebrado", "renegotiated" => "renegociado",
    "open" => "aberta", "handled" => "tratada", "all" => "todas", "none" => "sem_promessa", "in_force" => "em_vigor", "scheduled" => "agendada", "ended" => "encerrada",
    "batch" => "lote", "rule" => "regra", "team" => "equipe",
    "no_address" => "sem_endereco",
    "valid" => "valido", "invalid" => "invalido", "do_not_disturb" => "nao_perturbe", "active" => "ativa", "suspended" => "suspensa",
    # Comandos da régua (21, R441): o estado do comando e o tipo da ação.
    "queued" => "na_fila", "executed" => "executado", "failed" => "falhou", "no_return" => "sem_retorno", "discarded" => "descartado",
    "letter" => "carta", "issue_instrument" => "emissao", "proposal" => "proposta", "promise" => "promessa", "task" => "tarefa",
    "negativation" => "negativacao", "protest" => "protesto", "lawsuit" => "ajuizamento", "credit_suspension" => "suspensao_do_credito",
    # Meio e ambiente da integração (16, revisão 1): "Criar integração" e "Trocar fornecedor" levam os dois no endereço.
    "card" => "cartao", "sandbox" => "homologacao", "production" => "producao"
  }.freeze
  INTERNAL = VALUES.invert.freeze

  module_function

  def to_url(value) = VALUES.fetch(value.to_s, value.to_s)

  def from_url(value) = value.is_a?(String) ? INTERNAL.fetch(value, value) : value
end
