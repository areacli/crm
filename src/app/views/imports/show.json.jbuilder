# Página da importação na SPA (R10, R56, R63; 05, 06, 09; decisão 0025): situação e andamento, confirmar ou descartar, o resultado da conferência (ou o que
# foi gravado) de cada tipo, as seções da carga de carteira e as linhas recusadas. Os valores saem formatados, como nas páginas do servidor.
import = @import
data = import.summary_data
par = ->(rotulo, valor, detalhe = nil) { { rotulo: rotulo, valor: valor, detalhe: detalhe } }
json.id import.id
json.credor import.tenant.name
json.recebida datetime_br(import.created_at)
json.arquivo "#{import.original_name} (#{number_br(import.size_bytes / 1024)} KB)"
json.tipo(import.portfolio? ? "#{t("imports.kinds.#{import.kind}")} (#{t("imports.modes.#{import.mode}").downcase})" : t("imports.kinds.#{import.kind}"))
json.enviada_por(import.user&.name || "—")
json.partial! "imports/selo", import: import
json.andamento import.progress_label.presence
json.falha(import.rejected? || import.failed? ? import.failure_reason.presence || "A importação não pôde ser concluída." : nil)
json.pode_confirmar policy(import).confirm?
json.mensagem_de_confirmar(t("imports.confirm_message.#{import.kind}") + (import.portfolio? && import.full_sync? ? " Os que não vieram no arquivo saem da cobrança." : ""))
json.mensagem_de_descartar t("imports.discard_message.#{import.kind}")

resultado = nil
if data.present?
  colunas_ignoradas = ("Colunas ignoradas: #{data[:ignored_columns].join(", ")}." if data[:ignored_columns].present?)
  titulo = import.confirmed? ? "O que foi gravado" : "Resultado da conferência"
  case import.kind
  when "portfolio"
    pares = [ par.("Linhas lidas", number_br(data[:lines])), par.("Títulos válidos", number_br(data[:valid])), par.("Linhas recusadas", number_br(data[:rejected])),
              par.("Clientes", number_br(data[:customers]), "#{number_br(data[:customers_new])} novos"), par.("Valor dos títulos", "R$ #{data[:amount_formatted]}"),
              par.("Títulos novos", number_br(data[:bills_new])), par.("Títulos atualizados", number_br(data[:bills_updated])), par.("Títulos sem mudança", number_br(data[:bills_unchanged])) ]
    pares << par.("Títulos reincluídos", number_br(data[:bills_reincluded])) if data[:bills_reincluded].to_i.positive?
    pares << par.("Títulos a retirar", number_br(data.dig(:to_withdraw, :count)), "R$ #{Money.format(data.dig(:to_withdraw, :amount_cents).to_i)}") if import.full_sync?
    notas = [ colunas_ignoradas ]
    notas << "#{number_br(data[:contracts_created_by_omission])} clientes sem contrato no arquivo ganharam um contrato criado por omissão." if data[:contracts_created_by_omission].to_i.positive?
  when "payments"
    effect = (import.confirmed? ? data[:confirmed_effect] : data[:effect]) || {}
    pares = [ par.("Linhas lidas", number_br(data[:lines])), par.("Pagamentos válidos", number_br(data[:valid]), "R$ #{data[:amount_formatted]}"), par.("Linhas recusadas", number_br(data[:rejected])),
              par.("Já registrados, ignorados", number_br(data[:ignored])), par.("Títulos quitados", number_br(effect[:settled])), par.("Baixas parciais", number_br(effect[:partial])),
              par.("Valor aplicado aos títulos", money(effect[:applied_cents].to_i)) ]
    pares << par.("Títulos pagos com abatimento", number_br(effect[:abated]), "#{money(effect[:abated_cents].to_i)}, estado final do credor ou tolerância de valor") if effect[:abated].to_i.positive?
    if effect[:agreement_payments].to_i.positive?
      pares << par.("Pagamentos de acordo", number_br(effect[:agreement_payments]), "pelo número de um título de acordo ou do acordo; efetivação, mora e quitação são conferidas na confirmação")
    end
    pares << par.("Créditos gerados", number_br(effect[:credits]), money(effect[:credit_cents].to_i))
    pares << par.("Pendentes novos", number_br(effect[:pending_new]), money(effect[:pending_cents].to_i))
    pares << par.("Pendentes de antes, aplicados", number_br(effect[:pending_applied])) if effect[:pending_applied].to_i.positive?
    notas = [ colunas_ignoradas ]
    notas << "Pendente é o pagamento cujo título ainda não está na carteira: fica sem efeito e sem crédito até uma carga de carteira trazer o título." if effect[:pending_new].to_i.positive?
  when "reversals"
    effect = (import.confirmed? ? data[:confirmed_effect] : data[:effect]) || {}
    pares = [ par.("Linhas lidas", number_br(data[:lines])), par.("Estornos válidos", number_br(data[:valid]), "R$ #{data[:amount_formatted]}"), par.("Linhas recusadas", number_br(data[:rejected])),
              par.("Já registrados, ignorados", number_br(data[:ignored])), par.("Títulos que voltam à cobrança", number_br(effect[:reopened])), par.("Saiu do título", money(effect[:from_bill_cents].to_i)),
              par.("Créditos reduzidos", number_br(effect[:credit_reduced]), money(effect[:from_credit_cents].to_i)), par.("Pendentes afetados", number_br(effect[:pending_reduced])) ]
    notas = [ colunas_ignoradas ]
  end
  resultado = { titulo: titulo, pares: pares, notas: notas.compact }
end
json.resultado resultado

# Seções só da carga de carteira (06, 05, 09).
avisos = nil
if import.portfolio? && data[:contact_warnings].to_i.positive?
  warnings = import.warnings.order(:line, :id).limit(50)
  avisos = { titulo: "Contatos com aviso: #{number_br(data[:contact_warnings])}",
             ajuda: "Os títulos e os demais dados da linha entram; só o contato avisado é ignorado ou entra inválido. Mostrando os primeiros #{number_br(warnings.size)}.",
             linhas: warnings.map { |warning| "linha #{warning.line}: #{warning.reason}" } }
end
json.avisos_de_contato avisos

kept = data[:kept_by_tenant]
mantidos = nil
if import.portfolio? && kept && (kept.dig(:names, :count).to_i + kept.dig(:contacts, :count).to_i).positive?
  efeito = data[:correction_policy] == "load" ? "a carga vence" : "mantido pelo credor"
  nomes = kept[:names][:count].to_i
  contatos = kept[:contacts][:count].to_i
  mantidos = {
    titulo: "Mantidos pelo credor: #{number_br(nomes)} #{nomes == 1 ? "nome" : "nomes"}, #{number_br(contatos)} #{contatos == 1 ? "contato" : "contatos"}",
    ajuda: "Dados corrigidos ou decididos na tela que a carga queria mudar. Política do credor: #{t("registry.correction_policies.#{data[:correction_policy]}").downcase}. Mostrando até 50 de cada.",
    linhas: kept[:names][:items].map { |item| { cliente: item[:current_name], dado: "Nome", hoje: item[:current_name], carga: item[:load_name], efeito: efeito } } +
            kept[:contacts][:items].map do |item|
              situacao = t("registry.statuses.#{item[:status]}").downcase
              { cliente: item[:customer], dado: t("registry.kinds.#{item[:kind]}"), hoje: "#{item[:value]} (#{situacao})", carga: item[:value],
                efeito: data[:correction_policy] == "load" ? "volta a válido, a carga vence" : "continua #{situacao}, mantido pelo credor" }
            end
  }
end
json.mantidos mantidos

discrepancies = data[:discrepancies]
divergencias = nil
if import.portfolio? && discrepancies && discrepancies[:count].to_i.positive?
  total = discrepancies[:count].to_i
  divergencias = {
    titulo: "Divergências de valor: #{number_br(total)} #{total == 1 ? "título" : "títulos"}",
    ajuda: "Títulos com pagamento cujo valor muda. Política do credor: #{t("discrepancies.policies.#{data[:discrepancy_policy]}").downcase}.#{" Mostrando os primeiros #{number_br(discrepancies[:items].size)}." if total > discrepancies[:items].size}",
    linhas: discrepancies[:items].map do |item|
      { titulo: item[:number], cliente: item[:customer], vigente: money(item[:previous_cents]), informado: money(item[:reported_cents]), pago: money(item[:allocated_cents]),
        saldo_antes: money(item[:balance_before_cents]), saldo_depois: money(item[:balance_after_cents]), excedente: item[:excess_cents].to_i.positive? ? money(item[:excess_cents]) : "—",
        efeito: t("discrepancies.effects.#{item[:effect]}") }
    end
  }
end
json.divergencias divergencias

reported = data[:reported_surcharges]
acrescimos = nil
if import.portfolio? && reported && reported[:lines].to_i.positive?
  acrescimos = [ par.("Linhas com acréscimo", number_br(reported[:lines])), par.("Multa", money(reported[:penalty_cents])), par.("Juros", money(reported[:interest_cents])),
                 par.("Correção", money(reported[:correction_cents])), par.("Outros", money(reported[:other_cents])) ]
end
json.acrescimos_informados acrescimos

comparison = data[:surcharge_comparison]
comparacao = nil
if import.portfolio? && comparison.present?
  momento = if comparison[:moment] == "after"
    "Com o valor atualizado já recalculado e o item exato do enquadramento financeiro."
  else
    "Aproximação com o item atual do enquadramento financeiro do contrato (\"Demais\" para contrato novo): aparece a tempo de desistir da carga."
  end
  comparacao = {
    ajuda: "#{momento} Só para conferência: o valor e o saldo dos títulos não mudam.",
    totais: comparison[:totals].map do |item|
      { componente: item[:name] == "fees" ? "Honorários (outros do credor)" : component_label(item[:name]), informado: money(item[:informed]), calculado: money(item[:calculated]), diferenca: money(item[:difference]) }
    end,
    legenda: ("As #{comparison[:largest].size} maiores diferenças entre #{number_br(comparison[:lines])} títulos com acréscimos." if comparison[:largest].any?),
    com_linha: comparison[:largest].first&.dig(:line).present?,
    maiores: comparison[:largest].map do |item|
      { titulo: item[:number], linha: item[:line] ? number_br(item[:line]) : "", informado: money(item[:informed_total]), calculado: money(item[:calculated_total]), diferenca: money(item[:difference]) }
    end
  }
end
json.comparacao comparacao

recusadas = nil
if @rejections.any?
  recusadas = { titulo: "Linhas recusadas#{" e ignoradas" if import.rejections.where(ignored: true).exists?}",
                ajuda: "Mostrando as primeiras #{@rejections.size} de #{number_br(import.rejections.count)}.",
                linhas: @rejections.map { |rejection| { linha: rejection.line, motivo: rejection.reason } } }
end
json.recusadas recusadas
