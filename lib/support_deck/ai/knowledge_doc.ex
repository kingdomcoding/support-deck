defmodule SupportDeck.AI.KnowledgeDoc do
  use Ash.Resource,
    domain: SupportDeck.AI,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "knowledge_docs"
    repo SupportDeck.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content, :string, allow_nil?: false, public?: true

    attribute :content_type, :atom do
      constraints one_of: [:doc, :resolved_ticket, :faq]
      allow_nil? false
      public? true
    end

    attribute :source_url, :string, public?: true
    attribute :metadata, :map, default: %{}, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :add do
      accept [:content, :content_type, :source_url, :metadata]
    end

    update :update_content do
      accept [:content, :metadata]
    end

    read :all_docs do
      prepare fn query, _ctx ->
        Ash.Query.sort(query, inserted_at: :desc)
      end
    end
  end
end
