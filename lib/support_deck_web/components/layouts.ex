defmodule SupportDeckWeb.Layouts do
  use SupportDeckWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-50">
      <nav class="w-64 bg-white border-r border-gray-200 flex flex-col">
        <div class="p-4 border-b border-gray-200">
          <a href="/" class="flex items-center gap-2">
            <div class="w-8 h-8 bg-indigo-600 rounded-lg flex items-center justify-center">
              <span class="text-white font-bold text-sm">SD</span>
            </div>
            <span class="font-semibold text-gray-900">SupportDeck</span>
          </a>
        </div>

        <div class="flex-1 overflow-y-auto py-4">
          <div class="px-3 mb-2">
            <p class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Monitor</p>
          </div>
          <.nav_link path={~p"/"} current={assigns[:current_path]} label="Overview" icon="hero-home" />
          <.nav_link path={~p"/tickets"} current={assigns[:current_path]} label="Tickets" icon="hero-inbox" badge={assigns[:ticket_count]} />
          <.nav_link path={~p"/sla"} current={assigns[:current_path]} label="SLA Dashboard" icon="hero-clock" badge={assigns[:breach_count]} badge_color="red" />
          <.nav_link path={~p"/ai"} current={assigns[:current_path]} label="AI Performance" icon="hero-cpu-chip" />
          <.nav_link path={~p"/integrations"} current={assigns[:current_path]} label="Integrations" icon="hero-puzzle-piece" />

          <div class="px-3 mt-6 mb-2">
            <p class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Configure</p>
          </div>
          <.nav_link path={~p"/rules"} current={assigns[:current_path]} label="Rules" icon="hero-bolt" badge={assigns[:rule_count]} badge_color="gray" />
          <.nav_link path={~p"/sla/policies"} current={assigns[:current_path]} label="SLA Policies" icon="hero-shield-check" />
          <.nav_link path={~p"/knowledge"} current={assigns[:current_path]} label="Knowledge Base" icon="hero-book-open" />
          <.nav_link path={~p"/settings"} current={assigns[:current_path]} label="Settings" icon="hero-cog-6-tooth" />

          <div class="px-3 mt-6 mb-2">
            <p class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Test</p>
          </div>
          <.nav_link path={~p"/simulator"} current={assigns[:current_path]} label="Simulator" icon="hero-beaker" />
          <.nav_link path={~p"/tour"} current={assigns[:current_path]} label="Guided Tour" icon="hero-map" />
        </div>

        <div class="p-4 border-t border-gray-200">
          <p class="text-xs text-gray-400">Ash + Phoenix + Oban</p>
        </div>
      </nav>

      <main class="flex-1 overflow-y-auto">
        <.flash_group flash={@flash} />
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :current, :string, default: nil
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :badge, :integer, default: nil
  attr :badge_color, :string, default: "indigo"

  defp nav_link(assigns) do
    active = assigns.current == assigns.path
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@path}
      class={"flex items-center gap-3 px-3 py-2 mx-2 rounded-lg text-sm #{if @active, do: "bg-indigo-50 text-indigo-700 font-medium", else: "text-gray-700 hover:bg-gray-100"}"}
    >
      <.icon name={@icon} class="size-5" />
      <span class="flex-1">{@label}</span>
      <span
        :if={@badge && @badge > 0}
        class={"px-2 py-0.5 text-xs rounded-full #{badge_classes(@badge_color)}"}
      >
        {@badge}
      </span>
    </a>
    """
  end

  defp badge_classes("red"), do: "bg-red-100 text-red-700"
  defp badge_classes("gray"), do: "bg-gray-100 text-gray-600"
  defp badge_classes(_), do: "bg-indigo-100 text-indigo-700"

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
