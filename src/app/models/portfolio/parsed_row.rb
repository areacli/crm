module Portfolio
  # Linha da planilha já validada e normalizada. `roles`: papéis declarados na coluna `papel`, separados por vírgula
  # (holder, financial_responsible); nil quando vazia (vale os dois).
  ParsedRow = Data.define(:line, :document, :name, :phone, :email, :contract, :number, :due_date, :amount_cents, :description, :roles)
end
