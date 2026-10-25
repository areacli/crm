# Abatimento (03, R46; 11, R226, R228a, R229): a diferença que o título recebeu como paga sem dinheiro, por componente. `creditor`: o estado final
# "quitado" do arquivo (N1); `tolerance`: a tolerância de valor (N3); `minimum`: o resto abaixo do mínimo para quebrar (R229); `early`: o desconto dos juros do parcelamento pelo pagamento antecipado (DA35). Só inserção:
# o estorno do pagamento grava as linhas negativas e o título volta a ser devido.
class Abatement < ApplicationRecord
  include TenantScoped

  KINDS = %w[creditor tolerance minimum early].freeze

  belongs_to :payment
  belongs_to :bill

  enum :kind, KINDS.index_with(&:itself), prefix: :by, validate: true
end
