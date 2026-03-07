defmodule SupportDeckWeb.Layouts do
  use SupportDeckWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil

  def app(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200">
      <nav class="w-60 bg-base-100 border-r border-base-300 flex flex-col">
        <div class="p-4 border-b border-base-300">
          <a href="/" class="flex items-center gap-2.5">
            <div class="w-8 h-8 bg-gradient-to-br from-emerald-500 to-teal-600 rounded-lg flex items-center justify-center shadow-sm">
              <.icon name="hero-lifebuoy" class="size-4.5 text-white" />
            </div>
            <div>
              <span class="font-semibold text-base-content text-[15px] leading-tight block">
                SupportDeck
              </span>
              <span class="text-[10px] text-base-content/50 leading-tight">Supabase Demo</span>
            </div>
          </a>
        </div>

        <div class="flex-1 overflow-y-auto py-3 px-2 space-y-5">
          <div>
            <p class="px-2 mb-1 text-[10px] font-semibold text-base-content/40 uppercase tracking-widest">
              Operate
            </p>
            <.nav_item
              path={~p"/"}
              current={assigns[:current_path]}
              icon="hero-squares-2x2"
              label="Dashboard"
            />
            <.nav_item
              path={~p"/tickets"}
              current={assigns[:current_path]}
              icon="hero-inbox-stack"
              label="Tickets"
              badge={assigns[:ticket_count]}
            />
            <.nav_item
              path={~p"/sla"}
              current={assigns[:current_path]}
              icon="hero-clock"
              label="SLA Monitor"
              badge={assigns[:breach_count]}
              badge_variant="error"
            />
          </div>

          <div>
            <p class="px-2 mb-1 text-[10px] font-semibold text-base-content/40 uppercase tracking-widest">
              Intelligence
            </p>
            <.nav_item
              path={~p"/ai"}
              current={assigns[:current_path]}
              icon="hero-sparkles"
              label="AI Triage"
            />
            <.nav_item
              path={~p"/rules"}
              current={assigns[:current_path]}
              icon="hero-bolt"
              label="Automation"
              badge={assigns[:rule_count]}
              badge_variant="neutral"
            />
            <.nav_item
              path={~p"/knowledge"}
              current={assigns[:current_path]}
              icon="hero-book-open"
              label="Knowledge"
            />
          </div>

          <div>
            <p class="px-2 mb-1 text-[10px] font-semibold text-base-content/40 uppercase tracking-widest">
              Platform
            </p>
            <.nav_item
              path={~p"/integrations"}
              current={assigns[:current_path]}
              icon="hero-puzzle-piece"
              label="Integrations"
            />
            <.nav_item
              path={~p"/settings"}
              current={assigns[:current_path]}
              icon="hero-cog-6-tooth"
              label="Settings"
            />
            <.nav_item
              path={~p"/simulator"}
              current={assigns[:current_path]}
              icon="hero-beaker"
              label="Simulator"
            />
          </div>
        </div>

        <div class="p-3 border-t border-base-300 flex items-center justify-between">
          <a
            href={~p"/tour"}
            class="flex items-center gap-1.5 text-sm text-primary hover:underline"
          >
            <.icon name="hero-play-circle" class="size-4" /> Tour
          </a>
          <button
            onclick="const html = document.documentElement; const current = html.getAttribute('data-theme'); const next = current === 'dark' ? 'light' : 'dark'; html.setAttribute('data-theme', next); localStorage.setItem('phx:theme', next);"
            class="p-1.5 rounded-md text-base-content/50 hover:text-base-content hover:bg-base-200 transition"
            title="Toggle theme"
          >
            <.icon name="hero-moon" class="size-4" />
          </button>
        </div>
      </nav>

      <main class="flex-1 overflow-y-auto bg-base-200">
        <.flash_group flash={@flash} />
        {@inner_content}
      </main>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :current, :string, default: nil
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :badge, :integer, default: nil
  attr :badge_variant, :string, default: "primary"

  defp nav_item(assigns) do
    active = assigns.current == assigns.path
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@path}
      class={[
        "flex items-center gap-2.5 px-2.5 py-1.5 rounded-md text-sm transition-colors",
        @active && "bg-primary/10 text-primary font-medium",
        !@active && "text-base-content/70 hover:text-base-content hover:bg-base-200"
      ]}
    >
      <.icon name={@icon} class="size-4" />
      <span class="flex-1">{@label}</span>
      <span
        :if={@badge && @badge > 0}
        class={[
          "min-w-[20px] text-center px-1.5 py-0.5 text-[10px] font-medium rounded-full",
          @badge_variant == "error" && "bg-error/15 text-error",
          @badge_variant == "neutral" && "bg-base-content/10 text-base-content/60",
          @badge_variant == "primary" && "bg-primary/15 text-primary"
        ]}
      >
        {@badge}
      </span>
    </a>
    """
  end

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
