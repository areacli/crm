# Histórico de alterações: só inserção (R8, R13, R14, R16, R18, R29, R116). `origin` diz de onde veio a mudança de cadastro (load, screen,
# contact_attempt) e `note` guarda o motivo digitado.
class Change < ApplicationRecord
  include TenantScoped

  belongs_to :user, optional: true
  belongs_to :import, optional: true

  # Caminho único de auditoria (decisão 0021): telas, serviços e lotes de importação registram a mudança pelo mesmo método. `subject` é o registro
  # alterado (o tipo vem do nome do modelo) e `actor` quem fez a mudança; `import` marca a carga de onde a mudança veio. Quem não tem o registro à mão
  # informa `subject_type:` e `subject_id:` no lugar de `subject`; `user:` e `tenant:` valem como `actor:` e `tenant_id:`.
  def self.record!(subject = nil, event = nil, tenant_id: nil, tenant: nil, actor: nil, user: nil, import: nil, **fields)
    create!(**entry(subject, event, tenant_id: tenant_id || tenant&.id, actor: actor || user, import: import, **fields))
  end

  # Muitas mudanças de uma vez (um lote da importação): cada item é `[subject, event, { field:, before:, after:, note:, origin: }]`, gravadas em um
  # único INSERT do Active Record, com os mesmos campos de `record!`. O histórico é só inserção e não tem validação nem callback.
  def self.record_many!(entries, tenant_id:, actor: nil, import: nil)
    return if entries.empty?

    now = Time.current
    insert_all!(entries.map { |subject, event, fields| entry(subject, event, tenant_id: tenant_id, actor: actor, import: import, occurred_at: now, **fields) })
  end

  def self.entry(subject, event, tenant_id:, actor:, import:, **fields)
    { tenant_id: tenant_id || subject.try(:tenant_id), user_id: actor&.id, import_id: import&.id, subject_type: subject&.class&.name&.underscore,
      subject_id: subject&.id, event: event, field: nil, before: nil, after: nil, note: nil, origin: nil }.merge(fields)
  end
  private_class_method :entry
end
