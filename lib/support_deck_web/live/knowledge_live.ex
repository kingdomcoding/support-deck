defmodule SupportDeckWeb.KnowledgeLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @content_types [:doc, :resolved_ticket, :faq]
  @product_areas ["auth", "database", "storage", "functions", "realtime", "dashboard", "billing", "general"]
  @tiers ["free", "pro", "team", "enterprise"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Knowledge Base")
     |> assign(:current_path, ~p"/knowledge")
     |> assign(:content_types, @content_types)
     |> assign(:product_areas, @product_areas)
     |> assign(:tiers, @tiers)
     |> assign(:filter_type, nil)
     |> assign(:mode, :index)
     |> assign(:selected_doc, nil)
     |> assign(:form_data, nil)
     |> load_docs()}
  end

  @impl true
  def handle_event("filter", %{"type" => ""}, socket) do
    {:noreply, socket |> assign(:filter_type, nil) |> load_docs()}
  end

  def handle_event("filter", %{"type" => type}, socket) do
    {:noreply, socket |> assign(:filter_type, String.to_existing_atom(type)) |> load_docs()}
  end

  def handle_event("new", _, socket) do
    {:noreply,
     socket
     |> assign(:mode, :new)
     |> assign(:selected_doc, nil)
     |> assign(:form_data, %{
       "content" => "",
       "content_type" => "doc",
       "source_url" => "",
       "product_area" => "",
       "tags" => "",
       "applicable_tiers" => []
     })}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.docs, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Document not found")}

      doc ->
        {:noreply,
         socket
         |> assign(:mode, :edit)
         |> assign(:selected_doc, doc)
         |> assign(:form_data, %{
           "content" => doc.content,
           "content_type" => to_string(doc.content_type),
           "source_url" => doc.source_url || "",
           "product_area" => get_in(doc.metadata, ["product_area"]) || "",
           "tags" => (get_in(doc.metadata, ["tags"]) || []) |> Enum.join(", "),
           "applicable_tiers" => get_in(doc.metadata, ["applicable_tiers"]) || []
         })}
    end
  end

  def handle_event("cancel", _, socket) do
    {:noreply,
     socket |> assign(:mode, :index) |> assign(:selected_doc, nil) |> assign(:form_data, nil)}
  end

  def handle_event("save", params, socket) do
    metadata = build_metadata(params)

    result =
      case socket.assigns.mode do
        :new ->
          SupportDeck.AI.add_knowledge_doc(%{
            content: params["content"],
            content_type: String.to_existing_atom(params["content_type"]),
            source_url: if(params["source_url"] != "", do: params["source_url"]),
            metadata: metadata
          })

        :edit ->
          SupportDeck.AI.update_knowledge_doc(socket.assigns.selected_doc, %{
            content: params["content"],
            metadata: metadata
          })
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:mode, :index)
         |> assign(:selected_doc, nil)
         |> assign(:form_data, nil)
         |> put_flash(:info, "Document saved")
         |> load_docs()}

      {:error, err} ->
        {:noreply,
         put_flash(socket, :error, "Save failed: #{ErrorHelpers.format_error(err)}")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.docs, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Document not found")}

      doc ->
        case SupportDeck.AI.delete_knowledge_doc(doc) do
          :ok ->
            {:noreply,
             socket
             |> assign(:mode, :index)
             |> assign(:selected_doc, nil)
             |> assign(:form_data, nil)
             |> put_flash(:info, "Document deleted")
             |> load_docs()}

          {:error, err} ->
            {:noreply, put_flash(socket, :error, "Delete failed: #{ErrorHelpers.format_error(err)}")}
        end
    end
  end

  defp build_metadata(params) do
    tags =
      (params["tags"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    tiers = List.wrap(params["applicable_tiers"] || [])

    metadata = %{}
    metadata = if params["product_area"] != "", do: Map.put(metadata, "product_area", params["product_area"]), else: metadata
    metadata = if tags != [], do: Map.put(metadata, "tags", tags), else: metadata
    metadata = if tiers != [], do: Map.put(metadata, "applicable_tiers", tiers), else: metadata
    metadata
  end

  defp load_docs(socket) do
    docs =
      case SupportDeck.AI.list_all_knowledge_docs() do
        {:ok, d} -> d
        _ -> []
      end

    filtered =
      case socket.assigns[:filter_type] do
        nil -> docs
        type -> Enum.filter(docs, &(&1.content_type == type))
      end

    assign(socket, :docs, filtered)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-6">
      <.page_header
        title="Knowledge Base"
        description="Documentation, resolved patterns, and FAQs used by AI triage."
      >
        <:actions>
          <button
            :if={@mode == :index}
            phx-click="new"
            class="px-3 py-1.5 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
          >
            + New Document
          </button>
        </:actions>
      </.page_header>

      <%= if @mode in [:new, :edit] do %>
        <div class="bg-base-100 rounded-lg border border-base-300 p-6 mb-6">
          <h2 class="text-lg font-semibold text-base-content mb-4">
            {if @mode == :new, do: "New Document", else: "Edit Document"}
          </h2>
          <form phx-submit="save" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Content Type
                </label>
                <select
                  name="content_type"
                  disabled={@mode == :edit}
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option
                    :for={ct <- @content_types}
                    value={ct}
                    selected={to_string(ct) == @form_data["content_type"]}
                  >
                    {ct}
                  </option>
                </select>
                <input
                  :if={@mode == :edit}
                  type="hidden"
                  name="content_type"
                  value={@form_data["content_type"]}
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">Source URL</label>
                <input
                  type="text"
                  name="source_url"
                  value={@form_data["source_url"]}
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content/80 mb-1">Content</label>
              <textarea
                name="content"
                rows="6"
                required
                class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
              >{@form_data["content"]}</textarea>
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Product Area
                </label>
                <select
                  name="product_area"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                >
                  <option value="">None</option>
                  <option
                    :for={area <- @product_areas}
                    value={area}
                    selected={@form_data["product_area"] == area}
                  >
                    {area}
                  </option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/80 mb-1">
                  Tags
                </label>
                <input
                  type="text"
                  name="tags"
                  value={@form_data["tags"]}
                  placeholder="auth, login, sso"
                  class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
                />
                <p class="text-[10px] text-base-content/40 mt-0.5">Comma-separated</p>
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content/80 mb-1">
                Applicable Tiers
              </label>
              <div class="flex gap-4">
                <label :for={tier <- @tiers} class="inline-flex items-center gap-1.5 text-sm">
                  <input
                    type="checkbox"
                    name="applicable_tiers[]"
                    value={tier}
                    checked={tier in (@form_data["applicable_tiers"] || [])}
                    class="rounded border-base-300"
                  />
                  {tier}
                </label>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <button
                type="submit"
                class="px-4 py-2 text-sm bg-primary text-primary-content rounded-lg hover:bg-primary/90"
                phx-disable-with="Saving..."
              >
                Save
              </button>
              <button
                type="button"
                phx-click="cancel"
                class="px-4 py-2 text-sm border border-base-300 rounded-lg hover:bg-base-200"
              >
                Cancel
              </button>
              <button
                :if={@mode == :edit}
                type="button"
                phx-click="delete"
                phx-value-id={@selected_doc.id}
                data-confirm="Delete this document?"
                class="ml-auto px-4 py-2 text-sm text-error border border-error/30 rounded-lg hover:bg-error/10"
              >
                Delete Document
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <div :if={@mode == :index} class="mb-4">
        <form phx-change="filter">
          <select
            name="type"
            class="px-3 py-2 border border-base-300 rounded-lg text-sm bg-base-100"
          >
            <option value="">All Types</option>
            <option :for={ct <- @content_types} value={ct} selected={@filter_type == ct}>
              {ct}
            </option>
          </select>
        </form>
      </div>

      <div
        :if={@docs == [] && @mode == :index}
        class="text-center py-12 bg-base-100 rounded-lg border border-base-300"
      >
        <p class="text-base-content/60">No documents found.</p>
      </div>

      <div :if={@docs != [] && @mode == :index} class="space-y-3">
        <div
          :for={doc <- @docs}
          class="bg-base-100 rounded-lg border border-base-300 p-4 cursor-pointer hover:border-primary/30 transition"
          phx-click="edit"
          phx-value-id={doc.id}
        >
          <div class="flex items-center gap-2 mb-2">
            <span class="px-2 py-0.5 text-xs rounded-full bg-primary/10 text-primary border border-primary/20">
              {doc.content_type}
            </span>
            <span :if={doc.source_url} class="text-xs text-base-content/40">
              {doc.source_url}
            </span>
          </div>
          <p class="text-sm text-base-content/80 line-clamp-3">{doc.content}</p>
          <p class="text-xs text-base-content/40 mt-2">
            {Calendar.strftime(doc.inserted_at, "%Y-%m-%d %H:%M")}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
