# Título (parcela, mensalidade, fatura): pertence a um contrato. Vencido ou a vencer é calculado todo dia, e não é gravado (R6).
class Bill < ApplicationRecord
  include TenantScoped

  belongs_to :contract
  belongs_to :customer
  # Sistema pai (17, R403, R406): o do contrato quando o título vem de um sistema; o CRM para o que nasce aqui (título de acordo, da quebra e de
  # estorno). Nunca muda. `external_id` é o id do título no sistema de id próprio.
  belongs_to :source_system
  # Título de acordo (a entrada e as parcelas) ou da quebra: pertence a um acordo (11, R225).
  belongs_to :agreement, optional: true
  # Título de estorno (11, R233): título comum do cliente criado pelo CRM, numerado a partir do acordo de origem e fora dele.
  belongs_to :origin_agreement, class_name: "Agreement", optional: true
  has_many :value_versions, class_name: "BillValueVersion", dependent: :restrict_with_error
  has_many :value_discrepancies, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  # `renegotiated`: título original de um acordo efetivado (11, R225); `scheduled`: título de acordo que existe, mas só passa a ser cobrado com a efetivação
  # (R221); `canceled`: título de acordo cancelado (quebra antes da efetivação, título único, reversão).
  enum :status, { active: "active", withdrawn: "withdrawn", paid: "paid", renegotiated: "renegotiated", scheduled: "scheduled", canceled: "canceled" }, validate: true
  enum :kind, { common: "common", agreement: "agreement", break: "break", reversal: "reversal" }, prefix: :kind, validate: true

  attr_readonly :source_system_id
  validates :external_id, length: { maximum: 100 }
  before_validation :assume_source_system, on: :create

  scope :agreement_titles, -> { where.not(kind: "common") }
  # Os títulos que são do acordo (a entrada, as parcelas e o título da quebra); o título de estorno é comum e fica fora dele (R233, AH1).
  scope :of_agreement, -> { where(kind: %w[agreement break]) }
  scope :overdue, ->(today = Date.current) { active.where(due_date: ...today) }
  scope :upcoming, ->(today = Date.current) { active.where(due_date: today..) }

  # O título de acordo que está em cobrança ou que ainda vai ser cobrado (a vencer): tem devido calculado pelos parâmetros do acordo.
  def status_in_collection? = active? || scheduled?

  # Tem devido calculado pelos parâmetros congelados de um acordo: título de acordo, da quebra ou de estorno.
  def ledgered? = !kind_common?

  def days_overdue(today = Date.current) = [ (today - due_date).to_i, 0 ].max

  # Quem decidiu a carga que criou o título, para a versão 1 do valor (R88); vazio fora da importação.
  attr_accessor :version_user

  # Todo título nasce com a versão 1 do valor (R88), em qualquer caminho: tela, serviço ou lote da importação.
  after_create { value_versions.create!(tenant: tenant, bill: self, amount_cents: amount_cents, import_id: last_import_id, user: version_user) }

  # Datas de cobrança (plano técnico da camada 23, decisão 2): o dia de Brasília em que o título saiu de cobrança (`closed_on`) e em que voltou a ela
  # (`reopened_on`). Delas sai o episódio de atraso (`ArrearsEpisode`): o título esteve vencido do dia seguinte ao vencimento (ou da volta) até a saída.
  # Este modelo é o ponto único da mudança de estado: o registro pelo callback abaixo; o conjunto por `change_status_to!`. Um teste de arquitetura
  # recusa `update_all` de estado de título fora daqui.
  before_save :track_collection_dates, if: -> { new_record? || will_save_change_to_status? }

  # Muda o estado de um conjunto de títulos (sem callbacks), com as datas de cobrança. Uso: `Bill.where(...).change_status_to!("canceled")`.
  def self.change_status_to!(status, on: Date.current)
    status = status.to_s
    now = Time.current
    if status == "active"
      where.not(status: "active").update_all(status: status, reopened_on: on, closed_on: nil, updated_at: now)
    else
      left = where(status: "active").update_all(status: status, closed_on: on, updated_at: now)
      left + where.not(status: [ "active", status ]).update_all(status: status, updated_at: now)
    end
  end

  # Saldo do título: valor vigente menos o alocado, nunca negativo (R89); o que passa do valor é excedente.
  def balance_cents = [ amount_cents - paid_cents, 0 ].max

  # Excedente: quanto o alocado passa do valor vigente quando o valor cai abaixo do que já foi pago (R90). Calculado, nunca gravado.
  def excess_cents = [ paid_cents - amount_cents, 0 ].max

  private
    # Sai de cobrança: o pago no dia do pagamento (o dia em que deixou de estar vencido), o resto no dia da mudança. Volta a ela: o dia da volta.
    # O título que já nasce pago (carga com o histórico) saiu de cobrança no dia do pagamento; o que nasce fora dela sem ter sido cobrado
    # (título de acordo agendado, cancelado) não tem data.
    def track_collection_dates
      # Na criação, o "antes" seria o padrão da coluna (`active`), e não um estado que o título teve.
      before = new_record? ? nil : status_in_database
      today = Date.current
      if status == "active"
        return if before.nil?

        self.reopened_on = today
        self.closed_on = nil
      elsif before == "active" || (before.nil? && status == "paid")
        self.closed_on = status == "paid" ? (paid_on || today) : today
      end
    end

    def assume_source_system
      return if source_system_id || tenant_id.nil?

      self.source_system = kind_common? ? contract&.source_system : SourceSystem.crm_of(tenant_id)
    end
end
