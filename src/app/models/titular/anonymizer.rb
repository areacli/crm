module Titular
  # Anonimização (07, R130 a R135, PG5): troca, sem volta, tudo o que identifica o cliente por um identificador sem significado, mantendo
  # valores, datas e situações. O cliente segue como participante anônimo dos contratos (R132a). Tudo em SQL de conjunto sobre uma lista de
  # clientes: a anonimização a pedido é a lista de um, a tarefa diária usa lotes (e, se um lote falha, refaz um a um para isolar a falha).
  class Anonymizer
    REMOVED = "removido na anonimização".freeze
    Sql = Portfolio::Sql

    # Um cliente a pedido: motivo e documento digitado são obrigatórios (R131), a relação em aberto recusa (R130) e a importação em andamento
    # também. Devolve o cliente.
    def self.on_request(customer, actor:, reason:, document:)
      reason = reason.to_s.strip
      raise Refused, I18n.t("titular.anonymize.reason_required") if reason.empty?
      raise Refused, I18n.t("titular.anonymize.document_mismatch") unless Document.normalize(document) == customer.document
      raise Refused, I18n.t("titular.anonymize.already") if customer.anonymized?

      ApplicationRecord.transaction do
        customer.lock!
        raise Refused, I18n.t("titular.anonymize.already") if customer.anonymized?
        raise Refused, I18n.t("titular.anonymize.retained") if customer.retained?
        raise Refused, I18n.t("titular.import_running") if Import.in_progress.exists?(tenant_id: customer.tenant_id)

        relations = OpenRelations.new(customer)
        raise Refused, I18n.t("titular.anonymize.open", relations: relations.message) if relations.any?

        new(actor: actor, form: "request", reason: reason[0, 300]).run(customer.tenant_id, [ customer.id ])
      end
      Broadcast.changed(customer.tenant)
      customer.reload
    end

    # Lote da tarefa diária: os clientes já foram escolhidos pela consulta de vencidos.
    def self.in_batch(tenant_id, ids) = ApplicationRecord.transaction(requires_new: true) { new(actor: nil, form: "retention", reason: nil).run(tenant_id, ids) }

    def initialize(actor:, form:, reason:)
      @actor = actor
      @form = form
      @reason = reason
    end

    # Devolve quantos clientes foram anonimizados.
    def run(tenant_id, ids)
      t = tenant_id
      Sql.execute("drop table if exists anon_targets")
      Sql.execute("drop table if exists anon_payments")
      Sql.run(<<~SQL, t, ids)
        create temporary table anon_targets on commit drop as
        select id as customer_id, document as old_document, name as old_name, 'X' || lpad(id::text, 13, '0') as new_document,
               'Cliente anonimizado nº ' || id as new_name
        from customers where tenant_id = ? and id in (?) and anonymized_at is null
      SQL
      count = Sql.one("select count(*) as n from anon_targets")["n"].to_i
      return 0 if count.zero?

      Sql.execute("create unique index on anon_targets (customer_id)")
      Sql.execute("create index on anon_targets (old_document)")
      Sql.execute("analyze anon_targets")
      targets = "(select customer_id from anon_targets)"

      # Pagamentos do cliente: os dos títulos dele (o documento é de quem pagou, pode ser outra pessoa) e os sem título com o documento dele.
      Sql.run(<<~SQL, t, t)
        create temporary table anon_payments on commit drop as
        select p.id, tg.new_document from payments p join bills b on b.id = p.bill_id join anon_targets tg on tg.customer_id = b.customer_id where p.tenant_id = ?
        union all
        select p.id, tg.new_document from payments p join anon_targets tg on tg.old_document = p.document where p.tenant_id = ? and p.bill_id is null
      SQL
      Sql.execute("create unique index on anon_payments (id)")

      scrub_summaries(t)
      scrub_history(targets)
      Sql.execute("delete from customer_contacts where customer_id in #{targets}")
      # 12: o instrumento de pagamento guarda nome, documento e endereço do pagador no momento da emissão; saem junto com o cadastro.
      Sql.execute("update payment_instruments set payer_name = tg.new_name, payer_document = tg.new_document, payer_address = '{}'::jsonb from anon_targets tg where payment_instruments.customer_id = tg.customer_id")
      # 12, parte C: o link de checkout também guarda uma cópia do pagador (e e-mail e telefone); saem junto, e o link deixa de abrir (cancelado).
      Sql.execute("update payment_checkouts set payer_name = tg.new_name, payer_document = tg.new_document, payer_address = '{}'::jsonb, payer_email = null, payer_phone = null, " \
                  "state = 'canceled' from anon_targets tg where payment_checkouts.customer_id = tg.customer_id")
      Sql.run("update contact_attempts set contact_used = case when contact_used is not null then ? end, text = case when text is not null then ? end " \
              "where customer_id in #{targets} and (contact_used is not null or text is not null)", REMOVED, REMOVED)
      Sql.execute("update bills set description = null where customer_id in #{targets} and description is not null")
      Sql.execute("update payments set document = ap.new_document from anon_payments ap where payments.id = ap.id")
      Sql.run("update payment_reversals set reason = ? where reason is not null and payment_id in (select id from anon_payments)", REMOVED)
      # 10, R132: o motivo de cancelamento e de recusa das promessas feitas pelo cliente é texto livre e sai também.
      Sql.run("update payment_promises set reason = ? where reason is not null and customer_id in #{targets}", REMOVED)
      scrub_agreements(t)
      Sql.run("update value_discrepancies set note = ? where note is not null and bill_id in (select id from bills where customer_id in #{targets})", REMOVED)
      Sql.run("update credits set note = ? where reason = 'transfer' and note is not null and contract_id in " \
              "(select cc.contract_id from contract_customers cc where cc.customer_id in #{targets})", REMOVED)
      Sql.run(<<~SQL, t)
        update webhook_events w set payload = jsonb_set(w.payload, '{data,document}', to_jsonb(tg.new_document))
        from anon_targets tg
        where w.tenant_id = ? and jsonb_typeof(w.payload #> '{data}') = 'object'
          and upper(regexp_replace(coalesce(w.payload #>> '{data,document}', ''), '[^0-9A-Za-z]', '', 'g')) = tg.old_document
      SQL

      # O registro (R134) é escrito antes de trocar o nome, para guardar o identificador novo, e nunca o documento nem o nome antigo.
      Sql.run(<<~SQL, t, @actor&.id, @reason, @form)
        insert into changes (tenant_id, user_id, subject_type, subject_id, event, field, before, after, note, origin, occurred_at)
        select ?, ?, 'customer', customer_id, 'anonymized', 'name', null, new_name, ?, ?, now() from anon_targets
      SQL
      Sql.execute("update customers set name = tg.new_name, document = tg.new_document, name_kept = false, anonymized_at = now(), updated_at = now() " \
                  "from anon_targets tg where customers.id = tg.customer_id")
      count
    end

    private
      # 11, R247, R132: nas propostas e nos acordos do cliente, o nome e o documento saem do termo guardado (de quem foi o cliente, os destinatários e quem aceitou), e os textos livres
      # (motivo de recusa, cancelamento e quebra, comprovante, eventos e decisões de estorno) também. Valores, datas e números ficam.
      def scrub_agreements(tenant_id)
        mapping = Sql.rows("select old_document, new_document, new_name, customer_id from anon_targets").to_h { |row| [ row["old_document"], row ] }
        by_customer = mapping.values.to_h { |row| [ row["customer_id"].to_i, row ] }
        scope = Agreement.where(tenant_id: tenant_id).where("customer_id in (select customer_id from anon_targets) or accepted_by_customer_id in (select customer_id from anon_targets) or " \
                            "exists (select 1 from anon_targets tg where position(tg.old_document in agreements.term_snapshot::text) > 0)")
        scope.find_each do |agreement|
          own = by_customer[agreement.customer_id]
          snapshot = agreement.term_snapshot.deep_dup
          rewrite = lambda do |hash|
            row = mapping[Document.normalize(hash["document"].to_s)]
            row ||= own if hash.equal?(snapshot["customer"])
            next unless row

            hash["name"] = row["new_name"]
            hash["document"] = row["new_document"]
          end
          rewrite.call(snapshot["customer"]) if snapshot["customer"]
          Array(snapshot["addressees"]).each { |hash| rewrite.call(hash) }
          snapshot["accepted_by"] = snapshot["accepted_by"].merge("name" => by_customer[agreement.accepted_by_customer_id]["new_name"]) if snapshot["accepted_by"] && by_customer[agreement.accepted_by_customer_id]
          attributes = { term_snapshot: snapshot }
          if own
            attributes[:reason] = REMOVED if agreement.reason.present?
            attributes[:reversal_reason] = REMOVED if agreement.reversal_reason.present?
            attributes[:proof] = REMOVED if agreement.proof.present?
          end
          agreement.update_columns(attributes)
          next unless own

          Sql.run("update agreement_events set data = data - 'reason' - 'note' || jsonb_build_object('reason', ?::text) where agreement_id = ? and (jsonb_exists(data, 'reason') or jsonb_exists(data, 'note'))", REMOVED, agreement.id)
          Sql.run("update changes set note = ? where subject_type = 'agreement' and subject_id = ? and note is not null", REMOVED, agreement.id)
        end
        Sql.run("update reversal_waits set note = ? where note is not null and agreement_id in (select id from agreements where customer_id in (select customer_id from anon_targets))", REMOVED)
      end

      # Histórico (R132): valores trocados no cadastro, nos contatos e nos acionamentos do cliente e na descrição dos títulos dele.
      def scrub_history(targets)
        sets = "before = case when before is not null then '#{REMOVED}' end, after = case when after is not null then '#{REMOVED}' end, " \
               "note = case when note is not null then '#{REMOVED}' end"
        Sql.execute("update changes set #{sets} where subject_type = 'customer' and subject_id in #{targets} and event <> 'anonymized'")
        Sql.execute("update changes set #{sets} where subject_type = 'customer_contact' and subject_id in (select id from customer_contacts where customer_id in #{targets})")
        Sql.execute("update changes set #{sets} where subject_type = 'contact_attempt' and subject_id in (select id from contact_attempts where customer_id in #{targets})")
        Sql.execute("update changes set #{sets} where subject_type = 'payment_promise' and subject_id in (select id from payment_promises where customer_id in #{targets})")
        Sql.execute("update changes set #{sets} where subject_type = 'bill' and field = 'description' and subject_id in (select id from bills where customer_id in #{targets})")
      end

      # Resumo das importações (R132, revisão 1): nomes de clientes e valores de contatos nas listas viram o identificador ou o aviso.
      def scrub_summaries(tenant_id)
        map = Sql.rows("select old_name, new_name from anon_targets").to_h { |row| [ row["old_name"], row["new_name"] ] }
        Sql.rows("select distinct k.value from customer_contacts k join anon_targets tg on tg.customer_id = k.customer_id").each { |row| map[row["value"]] = REMOVED }
        Import.where(tenant_id: tenant_id).where("jsonb_exists(summary, 'discrepancies') or jsonb_exists(summary, 'kept_by_tenant')").find_each do |import|
          scrubbed = scrub(import.summary, map)
          import.update_columns(summary: scrubbed) if scrubbed != import.summary
        end
      end

      def scrub(node, map)
        case node
        when Hash then node.transform_values { |value| scrub(value, map) }
        when Array then node.map { |value| scrub(value, map) }
        when String then map.fetch(node, node)
        else node
        end
      end
  end
end
