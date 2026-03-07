defmodule SupportDeckWeb.KnowledgeLive do
  use SupportDeckWeb, :live_view
  alias SupportDeckWeb.ErrorHelpers

  @content_types [:doc, :resolved_ticket, :faq]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Knowledge Base")
     |> assign(:current_path, ~p"/knowledge")
     |> assign(:content_types, @content_types)
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
       "metadata" => "{}"
     })}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    doc = Enum.find(socket.assigns.docs, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:mode, :edit)
     |> assign(:selected_doc, doc)
     |> assign(:form_data, %{
       "content" => doc.content,
       "content_type" => to_string(doc.content_type),
       "source_url" => doc.source_url || "",
       "metadata" => Jason.encode!(doc.metadata || %{})
     })}
  end

  def handle_event("cancel", _, socket) do
    {:noreply,
     socket |> assign(:mode, :index) |> assign(:selected_doc, nil) |> assign(:form_data, nil)}
  end

  def handle_event("save", params, socket) do
    case Jason.decode(params["metadata"]) do
      {:error, %Jason.DecodeError{} = err} ->
        {:noreply,
         put_flash(socket, :error, "Invalid JSON in metadata: #{Exception.message(err)}")}

      {:ok, metadata} ->
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
            {:noreply, put_flash(socket, :error, "Save failed: #{ErrorHelpers.format_error(err)}")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    doc = Enum.find(socket.assigns.docs, &(&1.id == id))

    case SupportDeck.AI.delete_knowledge_doc(doc) do
      :ok -> {:noreply, socket |> put_flash(:info, "Document deleted") |> load_docs()}
      {:error, err} -> {:noreply, put_flash(socket, :error, "Delete failed: #{ErrorHelpers.format_error(err)}")}
    end
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
      <.tech_banner patterns={["Ash resources", "Knowledge base"]} />

      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-gray-900">Knowledge Base</h1>
        <button
          :if={@mode == :index}
          phx-click="new"
          class="px-3 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
        >
          + New Document
        </button>
      </div>

      <%= if @mode in [:new, :edit] do %>
        <div class="bg-white rounded-lg border border-gray-200 p-6 mb-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">
            {if @mode == :new, do: "New Document", else: "Edit Document"}
          </h2>
          <form phx-submit="save" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Content Type</label>
                <select
                  name="content_type"
                  disabled={@mode == :edit}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
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
                <label class="block text-sm font-medium text-gray-700 mb-1">Source URL</label>
                <input
                  type="text"
                  name="source_url"
                  value={@form_data["source_url"]}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Content</label>
              <textarea
                name="content"
                rows="6"
                required
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >{@form_data["content"]}</textarea>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Metadata (JSON)</label>
              <textarea
                name="metadata"
                rows="2"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono"
              >{@form_data["metadata"]}</textarea>
            </div>
            <div class="flex gap-3">
              <button
                type="submit"
                class="px-4 py-2 text-sm bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="cancel"
                class="px-4 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      <% end %>

      <div :if={@mode == :index} class="mb-4">
        <form phx-change="filter">
          <select name="type" class="px-3 py-2 border border-gray-300 rounded-lg text-sm">
            <option value="">All Types</option>
            <option :for={ct <- @content_types} value={ct} selected={@filter_type == ct}>{ct}</option>
          </select>
        </form>
      </div>

      <div
        :if={@docs == [] && @mode == :index}
        class="text-center py-12 bg-white rounded-lg border border-gray-200"
      >
        <p class="text-gray-500">No documents found.</p>
      </div>

      <div :if={@docs != [] && @mode == :index} class="space-y-3">
        <div :for={doc <- @docs} class="bg-white rounded-lg border border-gray-200 p-4">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <div class="flex items-center gap-2 mb-2">
                <span class="px-2 py-0.5 text-xs rounded-full bg-indigo-50 text-indigo-700 border border-indigo-100">
                  {doc.content_type}
                </span>
                <span :if={doc.source_url} class="text-xs text-gray-400">{doc.source_url}</span>
              </div>
              <p class="text-sm text-gray-700 line-clamp-3">{doc.content}</p>
              <p class="text-xs text-gray-400 mt-2">
                {Calendar.strftime(doc.inserted_at, "%Y-%m-%d %H:%M")}
              </p>
            </div>
            <div class="flex gap-2 ml-4">
              <button
                phx-click="edit"
                phx-value-id={doc.id}
                class="text-sm text-indigo-600 hover:text-indigo-700"
              >
                Edit
              </button>
              <button
                phx-click="delete"
                phx-value-id={doc.id}
                data-confirm="Delete this document?"
                class="text-sm text-red-600 hover:text-red-700"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
