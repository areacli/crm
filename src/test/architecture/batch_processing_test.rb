require "test_helper"

# Processamento em lote com ORM (decisão 0021): a gravação de entidades de domínio nas importações, na baixa, no estorno, nas promessas e nos acordos é Active
# Record sobre os modelos, com a auditoria de sempre (`Change.record!`). SQL escrito à mão só lê (contagens, junções e agregações). Cobre as importações de
# carteira, pagamentos e estornos, os jobs, as pastas de promessas, acordos e pagamentos, o histórico e as tarefas de medição.
class BatchProcessingArchitectureTest < ActiveSupport::TestCase
  ROOT = Rails.root
  # Instruções de escrita em texto: INSERT INTO, UPDATE ... SET, DELETE FROM, COPY ... FROM, e o helper antigo de escrita em lote.
  WRITE_SQL = /\b(insert\s+into|update\s+[\w."]+\s+set|delete\s+from|copy\s+[\w.]+\s*\()|Sql\.(run|execute|copy_in)\b|copy_data|put_copy_data/i

  # Quem ainda pode escrever com `Sql.run`/`Sql.execute` (decisão 0021, esclarecimento da parte 2): o recálculo DERIVADO dos segmentos, que regrava a tabela de cálculo
  # (o valor atualizado, que também é derivado, entra por insert_all! do modelo) e a anonimização da 07, reescrita irreversível em conjunto.
  SET_BASED_WRITERS = %w[app/models/segments/recalculation.rb app/models/titular/anonymizer.rb].freeze

  def batch_files
    folders = %w[portfolio payments promises agreements].flat_map { |folder| Dir[ROOT.join("app/models/#{folder}/**/*.rb")] }
    jobs = %w[check_import_job confirm_import_job import_job_failure stale_imports_job].map { |name| ROOT.join("app/jobs/#{name}.rb").to_s }
    (folders + jobs + [ ROOT.join("app/models/change.rb"), ROOT.join("lib/measure_data.rb"), ROOT.join("lib/tasks/measure.rake") ].map(&:to_s)).reject { |file| file.end_with?("/portfolio/sql.rb") }
  end

  def offenders_in(files, pattern)
    files.filter_map do |file|
      lines = File.readlines(file).each_with_index.select { |line, _| line.sub(/#.*/, "").match?(pattern) }
      "#{file.delete_prefix("#{ROOT}/")}:#{lines.map { |_, index| index + 1 }.join(',')}" if lines.any?
    end
  end

  test "as importações, a baixa, o estorno, as promessas e os acordos não gravam entidade de domínio com SQL escrito à mão" do
    assert_empty offenders_in(batch_files, WRITE_SQL), "SQL de escrita em lote (decisão 0021): use os modelos e Change.record!"
  end

  test "as tarefas de medição carregam massa de dados por insert_all! dos modelos, sem SQL de escrita" do
    assert_empty offenders_in([ ROOT.join("lib/tasks/measure.rake").to_s, ROOT.join("lib/measure_data.rb").to_s ], /\binsert\s+into\b|\bgenerate_series\b|Sql\.(run|execute)/i)
  end

  test "Sql.run e Sql.execute só sobram nos recálculos derivados e na anonimização; ninguém usa copy_in" do
    users = Dir[ROOT.join("app/**/*.rb")].select { |file| File.read(file).sub(/#.*/, "").match?(/Sql\.(run|execute)\b/) }.map { |file| file.delete_prefix("#{ROOT}/") }
    assert_empty users - SET_BASED_WRITERS
    assert_empty Dir[ROOT.join("{app,lib}/**/*.{rb,rake}")].select { |file| File.read(file).match?(/copy_in|copy_data/) }
  end

  test "o histórico passa todo pelo Change.record! e Change.record_many!" do
    assert_empty Dir[ROOT.join("{app,lib}/**/*.{rb,rake}")].select { |file| File.read(file).sub(/#.*/, "").match?(/Change\.create!|Change\.insert/) }
  end

  test "os jobs de importação (carteira, pagamentos e estornos) são retomáveis e os lotes auditam pelo Change" do
    assert_includes CheckImportJob.ancestors, ActiveJob::Continuable
    assert_includes ConfirmImportJob.ancestors, ActiveJob::Continuable
    assert_match(/Change\.record_many!/, File.read(ROOT.join("app/models/portfolio/confirm_batch.rb")))
    assert_match(/Change\.record_many!/, File.read(ROOT.join("app/models/payments/processor.rb")))
    assert_match(/Change\.record_many!/, File.read(ROOT.join("app/models/payments/reversal_processor.rb")))
  end

  test "a regra de divergência em Ruby e a em SQL dão o mesmo resultado" do
    tenant = tenants(:alfa)
    contract = Contract.create!(tenant: tenant, code: "RULES", created_by_omission: false)
    customer = Customer.create!(tenant: tenant, document: "52998224725", name: "Regras")
    cases = [ [ "active", 0 ], [ "active", 3_000 ], [ "active", 10_000 ], [ "withdrawn", 10_000 ], [ "paid", 10_000 ] ]
    cases.each_with_index do |(status, paid), index|
      Bill.create!(tenant: tenant, contract: contract, customer: customer, number: "R-#{index}", due_date: Date.new(2026, 9, 1), amount_cents: 10_000, paid_cents: paid, status: status)
    end
    %w[follow keep].each do |policy|
      [ 2_000, 3_000, 10_000, 15_000 ].each do |reported|
        Bill.where(contract: contract).find_each do |bill|
          ruby = Portfolio::DiscrepancyRules.evaluate(bill, reported, policy)
          sql = Portfolio::Sql.one(<<~SQL, bill.id)
            select #{Portfolio::DiscrepancyRules.effect_sql(policy, reported)} as effect, #{Portfolio::DiscrepancyRules.balance_before_sql} as before,
                   #{Portfolio::DiscrepancyRules.balance_after_sql(policy, reported)} as after, #{Portfolio::DiscrepancyRules.excess_sql(policy, reported)} as excess
            from bills b where b.id = ?
          SQL
          assert_equal [ sql["effect"], sql["before"].to_i, sql["after"].to_i, sql["excess"].to_i ],
                       [ ruby.effect, ruby.balance_before_cents, ruby.balance_after_cents, ruby.excess_cents ], "#{policy} #{reported} #{bill.status} #{bill.paid_cents}"
        end
      end
    end
  end
end
