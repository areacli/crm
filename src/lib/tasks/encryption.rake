namespace :crm do
  namespace :encryption do
    desc "Mostra, por modelo e atributo cifrado, quantos registros ainda não estão na chave atual (12, R256)"
    task status: :environment do
      keys = Array(ActiveRecord::Encryption.config.primary_key).size
      puts "Chaves na lista: #{keys}. Cifra com a última (identificador #{KeyRotation.current_key_id})."
      rows = KeyRotation.new.status
      rows.each { |row| puts "  #{row.model}.#{row.attribute}: #{row.pending} pendente(s) de #{row.total}" }
      pending = rows.sum(&:pending)
      puts pending.zero? ? "Nenhum registro fora da chave atual: a chave antiga pode sair da lista." : "Ainda há #{pending} registro(s) fora da chave atual: rode crm:encryption:rotate."
    end

    desc "Regrava com a chave atual os registros cifrados com chave antiga, em lotes de 500; retomável (12, R255)"
    task rotate: :environment do
      run = KeyRotation.new.call
      puts "Rotação: #{run.processed} regravado(s), #{run.failed} falha(s). #{run.note}"
      abort "A rotação não terminou limpa: confira crm:encryption:status." unless run.succeeded?
    end
  end
end
