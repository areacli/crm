module Payments
  # Linhas de detalhe só-inserção da baixa e do estorno (alocação por componente e abatimento): uma baixa com encargos grava até cinco por pagamento, e uma
  # instrução por linha era o maior custo do lote (decisão 0021, parte 2, medição). Cada linha é montada pelo modelo e **validada** (enum do componente e do tipo,
  # pagamento e título presentes); o que passa vai ao banco em um `insert_all!` do próprio modelo. Não há callback nesses modelos, e a auditoria da baixa
  # (`Change.record_many!`) cobre o título.
  module DetailLines
    module_function

    def insert!(model, records)
      return if records.empty?

      records.each(&:validate!)
      model.insert_all!(records.map { |record| record.attributes.except("id", "created_at", "updated_at") }, returning: false)
    end
  end
end
