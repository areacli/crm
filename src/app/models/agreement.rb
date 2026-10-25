# Acordo por novação (11): renegociação de 1 a n títulos de um cliente, com desconto por componente, entrada e parcelas. Existem a proposta (pendente de aprovação, aprovada,
# recusada, não aprovada, expirada, cancelada) e o acordo aceito (aguardando efetivação, ativo em dia ou em atraso, quitado, quebrado); o renegociado (acordo sobre acordo) e o
# estorno que reabre o acordo encerrado vêm nas etapas 5 e 6. Tudo o que é do acordo fica congelado na proposta (R210), em `terms`.
class Agreement < ApplicationRecord
  include TenantScoped

  STATES = %w[pending approved refused not_approved expired canceled awaiting_effectuation active_on_time active_late settled broken renegotiated].freeze
  # Propostas: ainda não aceitas (R218). Prendem os títulos enquanto valem.
  PROPOSAL = %w[pending approved].freeze
  # O acordo aceito que ainda não terminou (os títulos ficam presos a ele).
  RUNNING = %w[awaiting_effectuation active_on_time active_late broken].freeze
  CHANNELS = %w[phone whatsapp email in_person].freeze
  MODES = %w[cash installments].freeze

  belongs_to :customer
  belongs_to :segment, optional: true
  belongs_to :user, optional: true
  belongs_to :decided_by, class_name: "User", optional: true
  belongs_to :accepted_by_customer, class_name: "Customer", optional: true
  belongs_to :registered_by, class_name: "User", optional: true
  belongs_to :reversal_by, class_name: "User", optional: true
  has_many :agreement_bills, dependent: :delete_all
  has_many :bills, through: :agreement_bills
  has_many :events, class_name: "AgreementEvent", dependent: :delete_all
  has_many :settlements, class_name: "AgreementSettlement", dependent: :delete_all

  enum :state, STATES.index_with(&:itself), prefix: :state, validate: true
  enum :mode, MODES.index_with(&:itself), prefix: :mode, validate: true

  scope :proposals, -> { where(state: PROPOSAL) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def proposal? = PROPOSAL.include?(state)

  # Em andamento depois do aceite: aguardando efetivação, ativo (em dia ou em atraso) ou quebrado.
  def running? = RUNNING.include?(state)

  def label = number

  # Último dia em que a proposta ainda vale (R217): o dia da montagem é o dia zero.
  def last_valid_day = valid_until

  def expired_on?(date = Date.current) = date > valid_until

  def installments = schedule.reject { |row| row["number"].to_i.zero? }

  def down_payment = schedule.find { |row| row["number"].to_i.zero? }

  def discounts_bp = discounts.transform_values(&:to_i)

  def frozen_policy(key) = terms.dig("policies", key.to_s)

  # --- Títulos e prazos do acordo aceito (R221 a R236) ---

  # Os títulos de acordo (a entrada, as parcelas e o título da quebra), do vencimento mais antigo para o mais novo.
  def titles = Bill.where(agreement_id: id).order(:due_date, :id)

  # Os títulos de estorno numerados a partir deste acordo (R233, AH1): títulos comuns do cliente, fora do acordo; não entram na soma dos restos, não quebram nem impedem a quitação.
  def reversal_titles = Bill.where(origin_agreement_id: id).order(:due_date, :id)

  # Em reversão (R239): entre os dois passos o acordo fica marcado; a tarefa diária não o quebra e os encargos não correm.
  def reversing? = reversing_since.present? && reverted_at.nil?

  # Os intervalos em que a contagem dos prazos e dos encargos parou (R239, N17): [{ "kind" => "reversal" ou "credit", "from" => data, "to" => data ou nil (em andamento) }].
  def frozen_spans = terms.fetch("frozen", [])

  # Os intervalos como datas, para o `Ledger` descontar dos encargos de atraso: [[de, até ou nil]].
  def frozen_ranges = frozen_spans.reject { |span| span["keep_charges"] }.map { |span| [ Date.iso8601(span["from"]), (Date.iso8601(span["to"]) if span["to"]) ] }

  # A data de onde contam a tolerância e os dias de quebra de um título que venceu em `due` (R239, X3, W1; R232b, N17). Na reversão desistida, o título vencido antes da marca retoma de onde
  # parou (a marca empurra o prazo pela duração dela) e o que venceu durante a marca conta da desistência. Quando o crédito deixa de cobrir, os dias de quebra contam desse dia.
  def counting_due(due)
    frozen_spans.reduce(due) do |date, span|
      from = Date.iso8601(span["from"])
      to = span["to"] && Date.iso8601(span["to"])
      next date unless to

      if span["kind"] == "reversal" && date < from then date + (to - from).to_i
      elsif date <= to && date >= from then to
      elsif span["kind"] == "credit" && date < from then to
      else date
      end
    end
  end

  # A entrada é o título de número 0 (`ACD-000001-00`).
  def entry_title = Bill.find_by(agreement_id: id, number: Agreements::Titles.number_of(self, 0))

  def calendar = Agreements::Calendar.new(terms.dig("square", "holidays").to_a.map { |text| Date.iso8601(text) })

  # Quando o prazo de um título acaba: o vencimento mais os dias, passando ao dia útil seguinte da praça congelada (R234). O acordo quebra no dia seguinte.
  def deadline(due, days) = calendar.next_business(counting_due(due) + days)

  # O prazo de um título (R234, N10): a tolerância ou os dias de quebra contados do vencimento, ou, no título que um estorno bancário reabriu com a política "prazo novo", da data
  # mais tardia entre o estorno e o vencimento (`composition["reopened_on"]`).
  def deadline_for(bill, days)
    base = counting_due(bill.due_date)
    reopened = bill.composition&.dig("reopened_on")
    base = [ base, Date.iso8601(reopened) ].max if reopened
    calendar.next_business(base + days)
  end

  def tolerance_days = terms.dig("segment", "tolerance_days").to_i
  def break_days = terms.dig("segment", "break_days").to_i

  # O mínimo para quebrar e efetivar (R229, M1), em centavos, pela política congelada: em reais, em percentual do valor líquido do acordo ou igual à tolerância de valor
  # dos títulos de acordo (em percentual, sobre o valor líquido). Zero quer dizer que qualquer resto conta.
  def minimum_cents
    policy = frozen_policy("minimum_to_break") || { "kind" => "cents", "value" => 0 }
    case policy["kind"]
    when "percent" then net_cents * policy["value"].to_i / 10_000
    when "tolerance" then Agreements::Policies.tolerance_of(frozen_policy("tolerance_agreement"), net_cents)
    else policy["value"].to_i
    end
  end

  def tolerance_spec = frozen_policy("tolerance_agreement")

  # Efetivado: os originais já passaram a renegociados (R225).
  def effectuated? = effectuated_at.present?

  # Evento de invalidação (a ficha do cliente, a lista e os pendentes se refazem sozinhos).
  after_commit :announce_change, on: %i[create update]

  private
    def announce_change = Agreements::Broadcast.changed(tenant, [ customer_id ])
end
