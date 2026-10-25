require "test_helper"

class PlatformCheckJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "transmite o sinal da fila no canal da plataforma" do
    assert_broadcast_on(PlatformChannel::STREAM, event: "platform-ping", queue: "imports", sent_at: Time.current.iso8601) do
      freeze_time { PlatformCheckJob.perform_now("imports") }
    end
  end

  test "as cinco filas são as do Sidekiq" do
    sidekiq = YAML.safe_load(ERB.new(Rails.root.join("config/sidekiq.yml").read).result, permitted_classes: [ Symbol ], symbolize_names: true)

    assert_equal PlatformCheckJob::QUEUES, sidekiq[:queues].map(&:to_s)
  end

  test "a tarefa enfileira um job em cada fila" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("crm:platform_check")

    assert_enqueued_jobs 5, only: PlatformCheckJob do
      Rake::Task["crm:platform_check"].reenable
      capture_io { Rake::Task["crm:platform_check"].invoke }
    end
    PlatformCheckJob::QUEUES.each { |queue| assert_enqueued_with(job: PlatformCheckJob, queue: queue, args: [ queue ]) }
  end
end
