module Portfolio
  # Linha da planilha já validada e normalizada. `roles`: papéis declarados na coluna `papel`, separados por vírgula
  # (holder, financial_responsible); nil quando vazia (vale os dois). `contacts` e `warnings`: contatos válidos da linha e avisos dos ignorados (06, R109, R111). Produto e acréscimos já aplicados pelo credor são opcionais (R101, R102).
  # `external_*`: os ids remotos da linha (17, R401); o do título e o do contrato só existem em sistema de id próprio. `started_on`: a data de
  # início do contrato (`inicio_contrato`), vazia quando a coluna não veio ou veio vazia.
  ParsedRow = Data.define(:line, :document, :name, :contacts, :warnings, :contract, :number, :due_date, :amount_cents, :description, :roles, :product, :penalty_cents, :interest_cents, :correction_cents, :other_cents,
                          :external_bill_id, :external_contract_id, :external_customer_id, :started_on)
end
