module Segments
  # Exemplos prontos para começar um segmento (13, R290, SG17): fixos do sistema, iguais para todos os credores; só preenchem o editor.
  module Examples
    Example = Data.define(:key, :name, :subject, :tree)

    LIST = [
      Example.new("atraso-longo", "Contratos com atraso longo", "contracts", { "all" => [ { "path" => "overdue_days", "op" => "gt", "value" => 90 } ] }),
      Example.new("sem-contato-valido", "Clientes sem contato válido", "customers", { "all" => [ { "path" => "contacts", "qualifier" => "valid", "quantifier" => "none" } ] }),
      Example.new("promessa-quebrada", "Contratos com promessa quebrada recente", "contracts",
                  { "all" => [ { "path" => "promises", "quantifier" => "some", "where" => { "field" => "state", "op" => "eq", "value" => "broken" }, "within_days" => 90 } ] }),
      Example.new("sem-acionamento", "Contratos sem acionamento em 30 dias", "contracts", { "all" => [ { "path" => "contact_attempts", "quantifier" => "none", "within_days" => 30 } ] })
    ].freeze

    module_function

    def find(key) = LIST.find { |example| example.key == key }
  end
end
