defmodule SupportDeckWeb.ErrorHelpers do
  def format_error(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    errors
    |> Enum.map(&format_error/1)
    |> Enum.join(", ")
  end

  def format_error(%Ash.Error.Changes.InvalidAttribute{field: field, message: message}) do
    "#{field} #{message}"
  end

  def format_error(%Ash.Error.Changes.Required{field: field}) do
    "#{field} is required"
  end

  def format_error(%{message: message}) when is_binary(message), do: message

  def format_error(err) when is_binary(err), do: err

  def format_error(err), do: inspect(err)
end
