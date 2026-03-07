defmodule SupportDeck.AI.Classification do
  defstruct [:product_area, :severity, :is_repetitive, :confidence, :reasoning]

  @type t :: %__MODULE__{
    product_area: atom(),
    severity: atom(),
    is_repetitive: boolean(),
    confidence: float(),
    reasoning: String.t() | nil
  }
end
