defmodule SupportDeck.Integrations.Linear.Client do
  @moduledoc """
  Linear GraphQL API client.

  Endpoint: POST https://api.linear.app/graphql
  Auth: API key (no Bearer prefix)
  Rate limits: 1,500 requests/hr + 250,000 complexity points/hr (leaky bucket)
  Pagination: Relay-style cursor-based (first/after, pageInfo.hasNextPage/endCursor)
  Priority values: 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low
  """

  @behaviour SupportDeck.Integrations.Linear.ClientBehaviour

  alias SupportDeck.Integrations.CircuitBreaker

  @endpoint "https://api.linear.app/graphql"

  @impl true
  def create_issue(attrs) do
    CircuitBreaker.call(:linear, fn ->
      query = """
      mutation IssueCreate($input: IssueCreateInput!) {
        issueCreate(input: $input) {
          success
          issue { id identifier title url }
        }
      }
      """

      input =
        %{
          title: attrs[:title],
          description: attrs[:description],
          teamId: attrs[:team_id],
          priority: attrs[:priority] || 4
        }
        |> maybe_put(:labelIds, attrs[:label_ids])
        |> maybe_put(:stateId, attrs[:state_id])
        |> maybe_put(:assigneeId, attrs[:assignee_id])

      case graphql(query, %{input: input}) do
        {:ok, %{"issueCreate" => %{"success" => true, "issue" => issue}}} -> {:ok, issue}
        {:ok, _} -> {:error, :issue_creation_failed}
        error -> error
      end
    end)
  end

  @impl true
  def get_issue(id) do
    CircuitBreaker.call(:linear, fn ->
      query = """
      query Issue($id: String!) {
        issue(id: $id) {
          id identifier title url priority
          state { id name type }
          assignee { id name email }
          team { id name key }
          labels { nodes { id name } }
        }
      }
      """

      case graphql(query, %{id: id}) do
        {:ok, %{"issue" => issue}} -> {:ok, issue}
        error -> error
      end
    end)
  end

  @impl true
  def create_attachment(issue_id, attrs) do
    CircuitBreaker.call(:linear, fn ->
      query = """
      mutation AttachmentCreate($input: AttachmentCreateInput!) {
        attachmentCreate(input: $input) {
          success
          attachment { id }
        }
      }
      """

      input = %{
        issueId: issue_id,
        title: attrs[:title],
        subtitle: attrs[:subtitle],
        url: attrs[:url],
        metadata: attrs[:metadata] || %{}
      }

      case graphql(query, %{input: input}) do
        {:ok, %{"attachmentCreate" => %{"success" => true}}} -> :ok
        {:ok, _} -> {:error, :attachment_creation_failed}
        error -> error
      end
    end)
  end

  @impl true
  def create_comment(issue_id, body) do
    CircuitBreaker.call(:linear, fn ->
      query = """
      mutation CommentCreate($input: CommentCreateInput!) {
        commentCreate(input: $input) {
          success
          comment { id body }
        }
      }
      """

      case graphql(query, %{input: %{issueId: issue_id, body: body}}) do
        {:ok, %{"commentCreate" => %{"success" => true, "comment" => comment}}} -> {:ok, comment}
        {:ok, _} -> {:error, :comment_creation_failed}
        error -> error
      end
    end)
  end

  defp graphql(query, variables) do
    api_key = SupportDeck.Settings.Resolver.get(:linear, :api_key)

    case Req.post(
           url: @endpoint,
           headers: [{"authorization", api_key}, {"content-type", "application/json"}],
           json: %{query: query, variables: variables}
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %{status: 200, body: %{"errors" => errors}}} ->
        {:error, errors}

      {:ok, %{status: 400, body: %{"errors" => [%{"extensions" => %{"code" => "RATELIMITED"}} | _]}}} ->
        {:error, {:rate_limited, 60}}

      {:ok, %{status: s, body: b}} ->
        {:error, %{status: s, body: b}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
