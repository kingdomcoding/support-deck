defmodule SupportDeck.Observability.Telemetry do
  require Logger

  def attach do
    :telemetry.attach_many(
      "support-deck-telemetry",
      [
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:oban, :job, :stop], measurements, metadata, _config) do
    Logger.info("Oban job completed",
      worker: metadata.worker,
      queue: metadata.queue,
      duration_ms: div(measurements.duration, 1_000_000)
    )
  end

  def handle_event([:oban, :job, :exception], _measurements, metadata, _config) do
    Logger.error("Oban job failed",
      worker: metadata.worker,
      queue: metadata.queue,
      error: inspect(metadata.error)
    )
  end
end
