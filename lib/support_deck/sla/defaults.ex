defmodule SupportDeck.SLA.Defaults do
  @moduledoc """
  SLA calculation helper. Uses hardcoded defaults that mirror Supabase's
  SLA Buddy blog post. Falls back to database SLAPolicy records if they exist.
  """

  @defaults %{
    {:enterprise, :critical} => 10,
    {:enterprise, :high} => 30,
    {:enterprise, :medium} => 60,
    {:enterprise, :low} => 120,
    {:team, :critical} => 60,
    {:team, :high} => 120,
    {:team, :medium} => 240,
    {:team, :low} => 480,
    {:pro, :critical} => 120,
    {:pro, :high} => 240,
    {:pro, :medium} => 480,
    {:pro, :low} => 960,
    {:free, :critical} => 240,
    {:free, :high} => 480,
    {:free, :medium} => 960,
    {:free, :low} => 1440
  }

  def deadline_minutes(tier, severity) do
    Map.get(@defaults, {tier, severity})
  end
end
