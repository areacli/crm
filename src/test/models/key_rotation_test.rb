require "test_helper"
require "rake"

# Chaves do Active Record Encryption (12, R252 a R257): a lista, a chave antiga que continua decifrando, a rotação em lotes e a verificação.
class KeyRotationTest < ActiveSupport::TestCase
  OLD = "chave-antiga-de-teste-0123456789abcdef0123456789abcdef".freeze
  NEW = "chave-nova-de-teste-0123456789abcdef0123456789abcdef".freeze

  Killed = Class.new(Exception) # rubocop:disable Lint/InheritException -- simula a morte do processo, que nenhum rescue comum pega

  setup do
    @alfa = tenants(:alfa)
    @old_provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new([ OLD ])
    @both = ActiveRecord::Encryption::DerivedSecretKeyProvider.new([ OLD, NEW ])
  end

  def with_old_key(store_references: true, &block)
    original = ActiveRecord::Encryption.config.store_key_references
    ActiveRecord::Encryption.config.store_key_references = store_references
    ActiveRecord::Encryption.with_encryption_context(key_provider: @old_provider, &block)
  ensure
    ActiveRecord::Encryption.config.store_key_references = original
  end

  def with_both_keys(&block) = ActiveRecord::Encryption.with_encryption_context(key_provider: @both, &block)

  def key_id(raw) = ActiveRecord::Encryption.message_serializer.load(raw).headers.encrypted_data_key_id

  test "as credenciais de teste trazem as três chaves e a configuração guarda a referência da chave (R252, R254)" do
    config = ActiveRecord::Encryption.config
    assert_predicate config.primary_key, :present?
    assert_predicate config.deterministic_key, :present?
    assert_predicate config.key_derivation_salt, :present?
    assert config.store_key_references
    assert_equal 1, Array(config.primary_key).size
  end

  test "a última chave da lista cifra e o cabeçalho diz qual (R254)" do
    channel = make_channel(@alfa)
    with_both_keys { channel.update!(webhook_secret: "abc") }
    new_id = ActiveRecord::Encryption::Key.derive_from(NEW).id
    old_id = ActiveRecord::Encryption::Key.derive_from(OLD).id
    assert_equal new_id, key_id(channel.reload.webhook_secret_before_type_cast)
    assert_not_equal old_id, new_id
    with_both_keys { assert_equal "abc", channel.reload.webhook_secret }
  end

  test "o que foi cifrado só com a chave antiga, sem referência, continua legível com a lista (R253)" do
    channel = make_channel(@alfa)
    with_old_key(store_references: false) { channel.update!(webhook_secret: "segredo-antigo") }
    assert_nil key_id(channel.reload.webhook_secret_before_type_cast), "cifrado como o inicializador antigo fazia: sem referência"
    with_both_keys { assert_equal "segredo-antigo", channel.reload.webhook_secret }
  end

  test "a rotação regrava em lotes só o que não está na chave atual e termina com zero pendentes (R255, R256)" do
    channels = (1..7).map { |n| make_channel(@alfa, code: "C#{n}") }
    with_old_key(store_references: false) { channels.each_with_index { |channel, n| channel.update!(webhook_secret: "s#{n}") } }
    with_both_keys do
      assert_equal 7, KeyRotation.new.status.find { |row| row.model == "PaymentChannel" }.pending
      run = KeyRotation.new(batch_size: 3).call
      assert_predicate run, :succeeded?
      assert_equal 7, run.processed
      assert_equal 0, KeyRotation.new.pending_total
      assert_equal channels.map { |channel| "s#{channels.index(channel)}" }, channels.map { |channel| channel.reload.webhook_secret }
      new_id = ActiveRecord::Encryption::Key.derive_from(NEW).id
      assert(channels.all? { |channel| key_id(channel.webhook_secret_before_type_cast) == new_id })
    end
  end

  test "interrompida no primeiro lote, a próxima execução fecha a anterior como falha e continua do que falta (R255)" do
    channels = (1..7).map { |n| make_channel(@alfa, code: "D#{n}") }
    with_old_key { channels.each { |channel| channel.update!(webhook_secret: "x") } }
    with_both_keys do
      assert_raises(Killed) { KeyRotation.new(batch_size: 3, after_batch: ->(batch) { raise Killed if batch == 1 }).call }
      assert_equal "running", TaskRun.where(name: KeyRotation::NAME).order(:id).last.status
      pending_after_kill = KeyRotation.new.pending_total
      assert_equal 4, pending_after_kill, "o primeiro lote (3) já tinha sido regravado"

      second = KeyRotation.new(batch_size: 3).call
      assert_equal pending_after_kill, second.processed, "só o que faltava foi tocado"
      assert_predicate second, :succeeded?
      first = TaskRun.where(name: KeyRotation::NAME).order(:id).first
      assert_equal [ "failed", "Interrupted" ], [ first.status, first.error_kind ]
      assert_equal 0, KeyRotation.new.pending_total
    end
  end

  test "rodar de novo sem pendentes não regrava nada (R255)" do
    make_channel(@alfa).update!(webhook_secret: "z")
    run = KeyRotation.new.call
    assert_equal [ 0, "succeeded" ], [ run.processed, run.status ]
  end

  test "registro que não decifra conta como falha e não para os outros (caso de exceção)" do
    good = make_channel(@alfa, code: "OK")
    bad = make_channel(@alfa, code: "RUIM")
    with_old_key { [ good, bad ].each { |channel| channel.update!(webhook_secret: "v") } }
    bad.update_columns(webhook_secret: bad.reload.webhook_secret_before_type_cast.sub(/"p":"./, '"p":"A'))
    run = with_both_keys { KeyRotation.new.call }
    assert_equal [ 1, 1, "failed" ], [ run.processed, run.failed, run.status ]
  end

  test "a conta de pagamento também entra na rotação (R255)" do
    account = with_old_key { make_account(@alfa, secrets: { "api_key" => "k1" }) }
    with_both_keys do
      assert_equal 1, KeyRotation.new.status.find { |row| row.model == "PaymentAccount" }.pending
      KeyRotation.new.call
      assert_equal 0, KeyRotation.new.pending_total
      assert_equal "k1", account.reload.secrets["api_key"]
    end
  end

  test "as tarefas de status e de rotação mostram o resumo e a rotação limpa termina sem erro (R255, R256)" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("crm:encryption:status")
    channel = make_channel(@alfa)
    with_old_key(store_references: false) { channel.update!(webhook_secret: "t") }
    with_both_keys do
      output, = capture_io { Rake::Task["crm:encryption:status"].tap(&:reenable).invoke }
      assert_includes output, "PaymentChannel.webhook_secret: 1 pendente(s) de 1"
      assert_includes output, "rode crm:encryption:rotate"
      output, = capture_io { Rake::Task["crm:encryption:rotate"].tap(&:reenable).invoke }
      assert_includes output, "Rotação: 1 regravado(s), 0 falha(s)."
      output, = capture_io { Rake::Task["crm:encryption:status"].tap(&:reenable).invoke }
      assert_includes output, "a chave antiga pode sair da lista"
    end
  end
end
