defmodule SupportDeck.AI do
  use Ash.Domain

  resources do
    resource SupportDeck.AI.TriageResult do
      define(:record_triage, action: :record, args: [:ticket_id])
      define(:record_feedback, action: :record_human_feedback)
      define(:list_triage_for_ticket, action: :for_ticket, args: [:ticket_id])
      define(:list_recent_triage, action: :recent, args: [:since])
    end

    resource SupportDeck.AI.KnowledgeDoc do
      define(:add_knowledge_doc, action: :add)
      define(:update_knowledge_doc, action: :update_content)
      define(:delete_knowledge_doc, action: :destroy)
      define(:list_all_knowledge_docs, action: :all_docs)
      define(:get_knowledge_doc, action: :read, get_by: [:id])
    end
  end
end
