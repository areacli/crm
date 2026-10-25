module Portfolio
  # Linha da planilha já validada e normalizada. `roles`: papéis declarados na coluna `papel`, separados por vírgula
  # (holder, financial_responsible); nil quando vazia (vale os dois). Produto e acréscimos já aplicados pelo credor são opcionais (R101, R102).
  ParsedRow = Data.define(:line, :document, :name, :phone, :email, :contract, :number, :due_date, :amount_cents, :description, :roles, :product, :penalty_cents, :interest_cents, :correction_cents, :other_cents)
end
