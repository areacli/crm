module Agreements
  # Tetos de desconto por componente e por escolha (11, R207, R209): { "installment" => { "interest" => 100, ... }, "cash" => { ... } }, em pontos
  # percentuais inteiros. Componente sem valor vale zero. Os componentes são os do valor atualizado (09, R169), na ordem da baixa (10, R195).
  module Caps
    COMPONENTS = Agreements::BASE_ORDER
    KINDS = %w[installment cash].freeze

    module_function

    def blank = KINDS.to_h { |kind| [ kind, {} ] }

    def get(caps, kind, component) = caps.to_h.dig(kind.to_s, component.to_s).to_i

    def valid?(caps)
      caps.is_a?(Hash) && caps.keys.all? { |kind| KINDS.include?(kind) } &&
        caps.values.all? { |row| row.is_a?(Hash) && row.all? { |component, value| COMPONENTS.include?(component) && value.is_a?(Integer) && value.between?(0, 100) } }
    end

    # Normaliza: todos os componentes presentes nas duas colunas, em inteiros.
    def normalize(caps) = KINDS.to_h { |kind| [ kind, COMPONENTS.to_h { |component| [ component, get(caps, kind, component) ] } ] }

    # Padrão da DA4 para quem não altera políticas financeiras: a metade de cada teto, para baixo, em pontos inteiros.
    def half(caps) = KINDS.to_h { |kind| [ kind, COMPONENTS.to_h { |component| [ component, get(caps, kind, component) / 2 ] } ] }

    # O menor de cada par (um limite nunca passa do teto do segmento).
    def clamp(caps, ceiling) = KINDS.to_h { |kind| [ kind, COMPONENTS.to_h { |component| [ component, [ get(caps, kind, component), get(ceiling, kind, component) ].min ] } ] }
  end
end
