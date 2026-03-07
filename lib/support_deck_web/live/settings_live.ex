defmodule SupportDeckWeb.SettingsLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @integrations [
    {:front, [api_token: "API Token", webhook_secret: "Webhook Secret"]},
    {:slack, [bot_token: "Bot Token", signing_secret: "Signing Secret"]},
    {:linear, [api_key: "API Key", webhook_secret: "Webhook Secret"]},
    {:openai, [api_key: "API Key"]},
    {:anthropic, [api_key: "API Key"]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:current_path, ~p"/settings")
     |> assign(:integrations, @integrations)
     |> assign(:testing, nil)
     |> assign(:test_result, nil)
     |> load_credentials()}
  end

  @impl true
  def handle_event(
        "save_credential",
        %{"integration" => integration, "key_name" => key_name, "value" => value},
        socket
      ) do
    if value == "" do
      {:noreply, put_flash(socket, :error, "Value cannot be empty")}
    else
      attrs = %{
        integration: String.to_existing_atom(integration),
        key_name: String.to_existing_atom(key_name),
        plaintext_value: value
      }

      case SupportDeck.Settings.store_credential(attrs) do
        {:ok, _} ->
          {:noreply, socket |> put_flash(:info, "Credential saved") |> load_credentials()}

        {:error, err} ->
          {:noreply, put_flash(socket, :error, "Save failed: #{ErrorHelpers.format_error(err)}")}
      end
    end
  end

  def handle_event("test_connection", %{"integration" => integration}, socket) do
    name = String.to_existing_atom(integration)
    socket = assign(socket, :testing, name)

    case SupportDeck.Settings.ConnectionTester.test(name) do
      {:ok, message} ->
        update_test_results(name, :ok, message)

        {:noreply,
         socket
         |> assign(:testing, nil)
         |> assign(:test_result, {:ok, message})
         |> load_credentials()}

      {:error, message} ->
        update_test_results(name, :error, message)

        {:noreply,
         socket
         |> assign(:testing, nil)
         |> assign(:test_result, {:error, message})
         |> load_credentials()}
    end
  end

  def handle_event("delete_credential", %{"id" => id}, socket) do
    credential = Enum.find(socket.assigns.credentials, &(&1.id == id))

    case SupportDeck.Settings.delete_credential(credential) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Credential deleted") |> load_credentials()}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Delete failed: #{ErrorHelpers.format_error(err)}")}
    end
  end

  defp update_test_results(integration, status, message) do
    case SupportDeck.Settings.list_for_integration(integration) do
      {:ok, creds} ->
        Enum.each(creds, fn cred ->
          SupportDeck.Settings.record_test_result(cred, %{status: status, message: message})
        end)

      _ ->
        :ok
    end
  end

  defp load_credentials(socket) do
    credentials =
      case SupportDeck.Settings.list_all_credentials() do
        {:ok, c} -> c
        _ -> []
      end

    assign(socket, :credentials, credentials)
  end

  defp find_credential(credentials, integration, key_name) do
    Enum.find(credentials, fn c -> c.integration == integration and c.key_name == key_name end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-6">
      <.page_header
        title="Settings"
        description="Encrypted credential vault using AES-256-GCM. Credentials are stored encrypted and cached in ETS."
        patterns={["AES-256-GCM vault", "ETS cache", "GenServer resolver"]}
      />

      <div
        :if={@test_result}
        class={[
          "mb-6 p-4 rounded-lg border",
          elem(@test_result, 0) == :ok && "bg-success/10 border-success/30",
          elem(@test_result, 0) != :ok && "bg-error/10 border-error/30"
        ]}
      >
        <p class={[
          "text-sm",
          elem(@test_result, 0) == :ok && "text-success",
          elem(@test_result, 0) != :ok && "text-error"
        ]}>
          {elem(@test_result, 1)}
        </p>
      </div>

      <div class="space-y-6">
        <div
          :for={{integration, keys} <- @integrations}
          class="bg-base-100 rounded-lg border border-base-300 p-6"
        >
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-semibold text-base-content capitalize">{integration}</h2>
            <button
              phx-click="test_connection"
              phx-value-integration={integration}
              disabled={@testing == integration}
              class="px-3 py-1.5 text-sm border border-base-300 rounded-lg hover:bg-base-200 disabled:opacity-50"
            >
              {if @testing == integration, do: "Testing...", else: "Test Connection"}
            </button>
          </div>

          <div class="space-y-4">
            <div :for={{key_name, label} <- keys}>
              <% existing = find_credential(@credentials, integration, key_name) %>
              <div class="flex items-end gap-3">
                <div class="flex-1">
                  <label class="block text-sm font-medium text-base-content/80 mb-1">{label}</label>
                  <div :if={existing} class="flex items-center gap-2 mb-1">
                    <span class="text-xs text-base-content/40">{existing.value_hint}</span>
                    <span class={[
                      "px-1.5 py-0.5 text-[10px] rounded",
                      status_class(existing.last_test_status)
                    ]}>
                      {existing.last_test_status}
                    </span>
                    <button
                      phx-click="delete_credential"
                      phx-value-id={existing.id}
                      data-confirm="Delete this credential?"
                      class="text-[10px] text-error hover:text-error/80"
                    >
                      delete
                    </button>
                  </div>
                  <form phx-submit="save_credential" class="flex gap-2">
                    <input type="hidden" name="integration" value={integration} />
                    <input type="hidden" name="key_name" value={key_name} />
                    <input
                      type="password"
                      name="value"
                      placeholder={if existing, do: "Update value...", else: "Enter value..."}
                      class="flex-1 px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                    />
                    <button
                      type="submit"
                      class="px-3 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
                      phx-disable-with="Saving..."
                    >
                      Save
                    </button>
                  </form>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_class(:ok), do: "bg-success/15 text-success"
  defp status_class(:error), do: "bg-error/15 text-error"
  defp status_class(_), do: "bg-base-content/10 text-base-content/60"
end
