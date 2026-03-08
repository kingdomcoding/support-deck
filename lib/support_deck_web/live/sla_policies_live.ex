defmodule SupportDeckWeb.SLAPoliciesLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @tiers [:free, :pro, :team, :enterprise]
  @severities [:low, :medium, :high, :critical]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "SLA Policies")
     |> assign(:current_path, ~p"/sla/policies")
     |> assign(:tiers, @tiers)
     |> assign(:severities, @severities)
     |> assign(:editing, nil)
     |> assign(:creating, nil)
     |> assign(:form, nil)
     |> load_policies()}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    policy = Enum.find(socket.assigns.policies, &(&1.id == id))

    form_data = %{
      "first_response_minutes" => to_string(policy.first_response_minutes),
      "resolution_minutes" => to_string(policy.resolution_minutes || "")
    }

    {:noreply, socket |> assign(:editing, id) |> assign(:creating, nil) |> assign(:form, form_data)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign(:creating, nil) |> assign(:form, nil)}
  end

  def handle_event("save", %{"first_response_minutes" => frm, "resolution_minutes" => rm}, socket) do
    case Enum.find(socket.assigns.policies, &(&1.id == socket.assigns.editing)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Policy not found")}

      policy ->
        with {frm_int, ""} <- Integer.parse(frm),
             true <- frm_int > 0 do
          attrs = %{first_response_minutes: frm_int}

          attrs =
            case Integer.parse(rm) do
              {rm_int, ""} when rm_int > 0 -> Map.put(attrs, :resolution_minutes, rm_int)
              _ -> attrs
            end

          case SupportDeck.SLADomain.update_policy(policy, attrs) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:editing, nil)
               |> assign(:form, nil)
               |> put_flash(:info, "Policy updated")
               |> load_policies()}

            {:error, err} ->
              {:noreply, put_flash(socket, :error, "Update failed: #{ErrorHelpers.format_error(err)}")}
          end
        else
          _ -> {:noreply, put_flash(socket, :error, "Minutes must be a positive number")}
        end
    end
  end

  def handle_event("new_policy", %{"tier" => tier, "severity" => severity}, socket) do
    tier_atom = String.to_existing_atom(tier)
    sev_atom = String.to_existing_atom(severity)
    default_response = SupportDeck.SLADomain.deadline_minutes(tier_atom, sev_atom) || 60

    form_data = %{
      "first_response_minutes" => to_string(default_response),
      "resolution_minutes" => to_string(default_response * 4)
    }

    {:noreply,
     socket
     |> assign(:creating, {tier_atom, sev_atom})
     |> assign(:editing, nil)
     |> assign(:form, form_data)}
  end

  def handle_event("create_policy", %{"first_response_minutes" => frm, "resolution_minutes" => rm}, socket) do
    {tier, severity} = socket.assigns.creating

    with {frm_int, ""} <- Integer.parse(frm),
         true <- frm_int > 0 do
      rm_int =
        case Integer.parse(rm) do
          {v, ""} when v > 0 -> v
          _ -> nil
        end

      attrs = %{
        name: "#{tier}/#{severity}",
        subscription_tier: tier,
        severity: severity,
        first_response_minutes: frm_int,
        resolution_minutes: rm_int,
        escalation_thresholds: %{"warning" => 80, "critical" => 100}
      }

      case SupportDeck.SLADomain.create_policy(attrs) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:creating, nil)
           |> assign(:form, nil)
           |> put_flash(:info, "Policy created")
           |> load_policies()}

        {:error, err} ->
          {:noreply, put_flash(socket, :error, "Create failed: #{ErrorHelpers.format_error(err)}")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Minutes must be a positive number")}
    end
  end

  def handle_event("delete_policy", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.policies, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Policy not found")}

      policy ->
        case SupportDeck.SLADomain.delete_policy(policy) do
          :ok ->
            {:noreply, socket |> put_flash(:info, "Policy deleted") |> load_policies()}

          {:error, err} ->
            {:noreply, put_flash(socket, :error, "Delete failed: #{ErrorHelpers.format_error(err)}")}
        end
    end
  end

  defp load_policies(socket) do
    policies =
      case SupportDeck.SLADomain.list_all_policies() do
        {:ok, p} -> p
        _ -> []
      end

    assign(socket, :policies, policies)
  end

  defp find_policy(policies, tier, severity) do
    Enum.find(policies, fn p -> p.subscription_tier == tier and p.severity == severity end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <div class="flex items-center gap-3 mb-2">
        <.link navigate={~p"/sla"} class="text-base-content/40 hover:text-base-content/60 text-sm">
          &larr; Back
        </.link>
      </div>
      <.page_header
        title="SLA Policies"
        description="Response and resolution time targets by subscription tier and severity. Grid-based inline editing."
        patterns={["Ash resource CRUD", "Upsert with identity"]}
      />

      <div class="bg-base-100 rounded-lg border border-base-300 overflow-hidden">
        <table class="min-w-full divide-y divide-base-300">
          <thead class="bg-base-200">
            <tr>
              <th class="px-4 py-3 text-left text-xs font-medium text-base-content/60 uppercase">
                Tier / Severity
              </th>
              <th
                :for={sev <- @severities}
                class="px-4 py-3 text-center text-xs font-medium text-base-content/60 uppercase"
              >
                {sev}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-base-300">
            <tr :for={tier <- @tiers}>
              <td class="px-4 py-3 text-sm font-medium text-base-content">{tier}</td>
              <td :for={sev <- @severities} class="px-4 py-3 text-center">
                <% policy = find_policy(@policies, tier, sev) %>
                <%= if policy do %>
                  <%= if @editing == policy.id do %>
                    <form phx-submit="save" class="space-y-1">
                      <div>
                        <label class="text-[10px] text-base-content/40">Response (min)</label>
                        <input
                          type="number"
                          name="first_response_minutes"
                          value={@form["first_response_minutes"]}
                          min="1"
                          required
                          class="w-20 px-1 py-0.5 text-xs border border-base-300 rounded bg-base-100"
                        />
                      </div>
                      <div>
                        <label class="text-[10px] text-base-content/40">Resolution (min)</label>
                        <input
                          type="number"
                          name="resolution_minutes"
                          value={@form["resolution_minutes"]}
                          min="1"
                          class="w-20 px-1 py-0.5 text-xs border border-base-300 rounded bg-base-100"
                        />
                      </div>
                      <div class="flex gap-1 items-center">
                        <button
                          type="submit"
                          class="px-2 py-0.5 text-[10px] bg-primary text-primary-content rounded"
                          phx-disable-with="..."
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit"
                          class="px-2 py-0.5 text-[10px] border border-base-300 rounded"
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          phx-click="delete_policy"
                          phx-value-id={policy.id}
                          data-confirm="Delete this SLA policy?"
                          class="ml-auto px-2 py-0.5 text-[10px] text-error border border-error/30 rounded hover:bg-error/10"
                        >
                          Delete
                        </button>
                      </div>
                    </form>
                  <% else %>
                    <button
                      phx-click="edit"
                      phx-value-id={policy.id}
                      class="text-left hover:bg-base-200 p-1 rounded w-full"
                    >
                      <p class="text-sm font-medium text-base-content">
                        {policy.first_response_minutes}m
                      </p>
                      <p class="text-[10px] text-base-content/40">
                        resolve: {policy.resolution_minutes || "—"}m
                      </p>
                    </button>
                  <% end %>
                <% else %>
                  <%= if @creating == {tier, sev} do %>
                    <form phx-submit="create_policy" class="space-y-1">
                      <div>
                        <label class="text-[10px] text-base-content/40">Response (min)</label>
                        <input
                          type="number"
                          name="first_response_minutes"
                          value={@form["first_response_minutes"]}
                          min="1"
                          required
                          class="w-20 px-1 py-0.5 text-xs border border-base-300 rounded bg-base-100"
                        />
                      </div>
                      <div>
                        <label class="text-[10px] text-base-content/40">Resolution (min)</label>
                        <input
                          type="number"
                          name="resolution_minutes"
                          value={@form["resolution_minutes"]}
                          min="1"
                          class="w-20 px-1 py-0.5 text-xs border border-base-300 rounded bg-base-100"
                        />
                      </div>
                      <div class="flex gap-1">
                        <button
                          type="submit"
                          class="px-2 py-0.5 text-[10px] bg-primary text-primary-content rounded"
                          phx-disable-with="..."
                        >
                          Create
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit"
                          class="px-2 py-0.5 text-[10px] border border-base-300 rounded"
                        >
                          Cancel
                        </button>
                      </div>
                    </form>
                  <% else %>
                    <button
                      phx-click="new_policy"
                      phx-value-tier={tier}
                      phx-value-severity={sev}
                      class="px-2 py-1 text-[10px] text-base-content/40 border border-dashed border-base-300 rounded hover:border-primary/30 hover:text-primary"
                    >
                      + Add
                    </button>
                  <% end %>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
