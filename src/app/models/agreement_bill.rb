# Um título do acordo (11, R211): a base e o desconto dele por componente (a linha "dívida" do arquivo) e o valor dele no acordo. `held` prende o título
# enquanto a proposta vale ou o acordo não terminou (R218); o índice único parcial do banco garante um título numa proposta vigente só.
class AgreementBill < ApplicationRecord
  belongs_to :agreement
  belongs_to :bill
  belongs_to :contract

  def base_total_cents = base.values.sum

  def discount_total_cents = discount.values.sum
end
