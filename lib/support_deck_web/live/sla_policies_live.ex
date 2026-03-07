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

    {:noreply, socket |> assign(:editing, id) |> assign(:form, form_data)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign(:form, nil)}
  end

  def handle_event("save", %{"first_response_minutes" => frm, "resolution_minutes" => rm}, socket) do
    policy = Enum.find(socket.assigns.policies, &(&1.id == socket.assigns.editing))

    attrs = %{
      first_response_minutes: String.to_integer(frm)
    }

    attrs =
      if rm != "", do: Map.put(attrs, :resolution_minutes, String.to_integer(rm)), else: attrs

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
  end

  def handle_event("create_default", %{"tier" => tier, "severity" => severity}, socket) do
    defaults =
      SupportDeck.SLADomain.deadline_minutes(
        String.to_existing_atom(tier),
        String.to_existing_atom(severity)
      )

    attrs = %{
      name: "#{tier}/#{severity}",
      subscription_tier: String.to_existing_atom(tier),
      severity: String.to_existing_atom(severity),
      first_response_minutes: defaults.first_response,
      resolution_minutes: defaults.resolution,
      escalation_thresholds: %{"warning" => 80, "critical" => 100}
    }

    case SupportDeck.SLADomain.create_policy(attrs) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Policy created") |> load_policies()}

      {:error, err} ->
        {:noreply, put_flash(socket, :error, "Create failed: #{ErrorHelpers.format_error(err)}")}
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
        <a href={~p"/sla"} class="text-base-content/40 hover:text-base-content/60 text-sm">
          &larr; Back
        </a>
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
                          class="w-20 px-1 py-0.5 text-xs border border-base-300 rounded bg-base-100"
                        />
                      </div>
                      <div>
                        <label class="text-[10px] text-base-content/40">Resolution (min)</label>
                        <input
                          type="number"
                          name="resolution_minutes"
                          value={@form["resolution_minutes"]}
                          class="w-20 px-1 py-0.5 text-xs border border-base-300 rounded bg-base-100"
                        />
                      </div>
                      <div class="flex gap-1">
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
                  <button
                    phx-click="create_default"
                    phx-value-tier={tier}
                    phx-value-severity={sev}
                    class="px-2 py-1 text-[10px] text-base-content/40 border border-dashed border-base-300 rounded hover:border-primary/30 hover:text-primary"
                  >
                    + Add
                  </button>
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
