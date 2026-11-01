# "Conferir" do editor de segmentos em segundo plano (13, R288, revisão 3).
class SegmentProbeJob < ApplicationJob
  queue_as :default

  def perform(id) = Segments::ProbeRun.compute(id)
end
