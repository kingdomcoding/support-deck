defmodule SupportDeckWeb.RulesLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @triggers [:ticket_created, :ticket_updated, :sla_breach, :customer_reply, :escalation]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rules")
     |> assign(:current_path, ~p"/rules")
     |> assign(:triggers, @triggers)
     |> load_rules()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:mode, :index)
    |> assign(:selected_rule, nil)
    |> assign(:form_data, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:mode, :new)
    |> assign(:selected_rule, nil)
    |> assign(:form_data, default_form())
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))

    if rule do
      socket
      |> assign(:mode, :edit)
      |> assign(:selected_rule, rule)
      |> assign(:form_data, %{
        "name" => rule.name,
        "description" => rule.description || "",
        "trigger" => to_string(rule.trigger),
        "conditions" => Jason.encode!(rule.conditions),
        "actions_list" => Jason.encode!(rule.actions_list),
        "enabled" => to_string(rule.enabled),
        "priority" => to_string(rule.priority)
      })
    else
      socket
      |> put_flash(:error, "Rule not found")
      |> push_patch(to: ~p"/rules")
    end
  end

  defp apply_action(socket, _, _params), do: apply_action(socket, :index, %{})

  defp default_form do
    %{
      "name" => "",
      "description" => "",
      "trigger" => "ticket_created",
      "conditions" => ~s|{"all": []}|,
      "actions_list" => "[]",
      "enabled" => "true",
      "priority" => "0"
    }
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))

    case SupportDeck.Tickets.update_rule(rule, %{enabled: !rule.enabled}) do
      {:ok, _} -> {:noreply, load_rules(socket)}
      {:error, err} -> {:noreply, put_flash(socket, :error, "Toggle failed: #{ErrorHelpers.format_error(err)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(&1.id == id))

    case SupportDeck.Tickets.delete_rule(rule) do
      :ok -> {:noreply, socket |> put_flash(:info, "Rule deleted") |> load_rules()}
      {:error, err} -> {:noreply, put_flash(socket, :error, "Delete failed: #{ErrorHelpers.format_error(err)}")}
    end
  end

  def handle_event("save", params, socket) do
    with {:ok, conditions} <- Jason.decode(params["conditions"]),
         {:ok, actions} <- Jason.decode(params["actions_list"]) do
      attrs = %{
        name: params["name"],
        description: params["description"],
        trigger: String.to_existing_atom(params["trigger"]),
        conditions: conditions,
        actions_list: actions,
        enabled: params["enabled"] == "true",
        priority: String.to_integer(params["priority"])
      }

      result =
        case socket.assigns.mode do
          :new -> SupportDeck.Tickets.create_rule(attrs)
          :edit -> SupportDeck.Tickets.update_rule(socket.assigns.selected_rule, attrs)
        end

      case result do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Rule saved")
           |> load_rules()
           |> push_patch(to: ~p"/rules")}

        {:error, err} ->
          {:noreply, put_flash(socket, :error, "Save failed: #{ErrorHelpers.format_error(err)}")}
      end
    else
      {:error, %Jason.DecodeError{} = err} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON: #{Exception.message(err)}")}
    end
  end

  defp load_rules(socket) do
    rules =
      case SupportDeck.Tickets.list_all_rules() do
        {:ok, r} -> r
        _ -> []
      end

    assign(socket, :rules, rules)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.tech_banner patterns={["Ash CRUD actions", "Rule engine", "Condition matching"]} />

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-base-content">Rules Engine</h1>
        <a
          :if={@mode == :index}
          href={~p"/rules/new"}
          class="px-3 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
        >
          + New Rule
        </a>
      </div>

      <%= if @mode in [:new, :edit] do %>
        <div class="bg-base-100 rounded-lg border border-base-300 p-6 mb-6">
          <h2 class="text-lg font-semibold text-base-content mb-4">
            {if @mode == :new, do: "New Rule", else: "Edit Rule"}
          </h2>
          <form phx-submit="save" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Name</label>
                <input
                  type="text"
                  name="name"
                  value={@form_data["name"]}
                  required
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Trigger</label>
                <select
                  name="trigger"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option
                    :for={t <- @triggers}
                    value={t}
                    selected={to_string(t) == @form_data["trigger"]}
                  >
                    {t}
                  </option>
                </select>
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content/80 mb-1">Description</label>
              <input
                type="text"
                name="description"
                value={@form_data["description"]}
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
              />
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Conditions (JSON)
                </label>
                <textarea
                  name="conditions"
                  rows="3"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm font-mono bg-base-100"
                >{@form_data["conditions"]}</textarea>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Actions (JSON)
                </label>
                <textarea
                  name="actions_list"
                  rows="3"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm font-mono bg-base-100"
                >{@form_data["actions_list"]}</textarea>
              </div>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Priority</label>
                <input
                  type="number"
                  name="priority"
                  value={@form_data["priority"]}
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Enabled</label>
                <select
                  name="enabled"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option value="true" selected={@form_data["enabled"] == "true"}>Yes</option>
                  <option value="false" selected={@form_data["enabled"] == "false"}>No</option>
                </select>
              </div>
            </div>
            <div class="flex gap-3">
              <button
                type="submit"
                class="px-4 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
              >
                Save
              </button>
              <a
                href={~p"/rules"}
                class="px-4 py-2 text-sm border border-base-300 rounded-lg hover:bg-base-200"
              >
                Cancel
              </a>
            </div>
          </form>
        </div>
      <% end %>

      <div
        :if={@rules == [] && @mode == :index}
        class="text-center py-12 bg-base-100 rounded-lg border border-base-300"
      >
        <p class="text-base-content/60">No rules configured yet.</p>
        <a
          href={~p"/rules/new"}
          class="text-primary hover:text-primary/80 text-sm mt-2 inline-block"
        >
          Create your first rule
        </a>
      </div>

      <div
        :if={@rules != [] && @mode == :index}
        class="bg-base-100 rounded-lg border border-base-300 overflow-hidden"
      >
        <table class="min-w-full divide-y divide-base-300">
          <thead class="bg-base-200">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Name
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Trigger
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Priority
              </th>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Status
              </th>
              <th class="px-4 py-3 text-right text-xs font-medium text-base-content/60 uppercase">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr :for={rule <- @rules} class="hover:bg-base-200">
              <td class="px-4 py-3">
                <p class="text-sm font-medium text-base-content">{rule.name}</p>
                <p :if={rule.description} class="text-xs text-base-content/60">
                  {rule.description}
                </p>
              </td>
              <td class="px-4 py-3 text-sm text-base-content/60">{rule.trigger}</td>
              <td class="px-4 py-3 text-sm text-base-content/60">{rule.priority}</td>
              <td class="px-4 py-3">
                <button
                  phx-click="toggle"
                  phx-value-id={rule.id}
                  class={[
                    "px-2 py-1 text-xs rounded-full",
                    rule.enabled && "bg-success/15 text-success",
                    !rule.enabled && "bg-base-content/10 text-base-content/60"
                  ]}
                >
                  {if rule.enabled, do: "Enabled", else: "Disabled"}
                </button>
              </td>
              <td class="px-4 py-3 text-right">
                <a
                  href={~p"/rules/#{rule.id}/edit"}
                  class="text-sm text-primary hover:text-primary/80 mr-3"
                >
                  Edit
                </a>
                <button
                  phx-click="delete"
                  phx-value-id={rule.id}
                  data-confirm="Delete this rule?"
                  class="text-sm text-error hover:text-error/80"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
