import { driver } from "driver.js"
import "driver.js/dist/driver.css"

const TOUR = [
  {
    path: "/",
    steps: [
      {
        element: "[data-tour='stats-grid']",
        popover: {
          title: "Live Metrics",
          description:
            "These cards update in real-time via PubSub. Every ticket create, triage, or escalation instantly refreshes the counts.",
          side: "bottom",
          align: "center",
        },
      },
      {
        element: "[data-tour='system-health']",
        popover: {
          title: "System Health",
          description:
            "Circuit breaker status for each integration. Green means healthy \u2014 if an external API fails repeatedly, the breaker trips to protect the system.",
          side: "left",
          align: "start",
        },
      },
    ],
  },
  {
    path: "/tickets",
    steps: [
      {
        element: "[data-tour='ticket-table']",
        popover: {
          title: "Ticket Lifecycle",
          description:
            "Each ticket flows through an Ash state machine \u2014 new \u2192 triaging \u2192 assigned \u2192 resolved. Click any row to see its full history and trigger transitions.",
          side: "top",
          align: "center",
        },
      },
      {
        element: "[data-tour='create-ticket-btn']",
        interactive: true,
        waitFor: "create_modal_opened",
        popover: {
          title: "Create a Ticket",
          description:
            "Click this button to open the ticket form. Try creating one \u2014 it\u2019ll appear instantly via PubSub.",
          side: "bottom",
          align: "end",
        },
      },
      {
        element: "[data-tour='create-form']",
        interactive: true,
        waitFor: "ticket_created",
        popover: {
          title: "Submit Your Ticket",
          description:
            "Fill in the details and submit. The ticket will get picked up by the AI triage worker and rule engine automatically.",
          side: "left",
          align: "start",
        },
      },
    ],
  },
  {
    path: "/sla",
    steps: [
      {
        element: "[data-tour='sla-stats']",
        popover: {
          title: "SLA Tracking",
          description:
            "Tier-aware SLA policies with configurable deadlines. AshOban triggers run on a schedule to check for breaches and auto-escalate.",
          side: "bottom",
          align: "center",
        },
      },
    ],
  },
  {
    path: "/rules",
    steps: [
      {
        element: "[data-tour='rules-table']",
        popover: {
          title: "Automation Engine",
          description:
            "Event-driven rules match conditions on ticket fields (severity, source, tier) and dispatch Oban worker actions like assign, notify, or escalate.",
          side: "top",
          align: "center",
        },
      },
    ],
  },
  {
    path: "/integrations",
    steps: [
      {
        element: "[data-tour='breaker-cards']",
        popover: {
          title: "Credentials & Circuit Breakers",
          description:
            "API keys are encrypted with AES-256-GCM and cached in ETS. Each integration has a GenServer-backed circuit breaker \u2014 trip one to simulate failures, then watch it recover.",
          side: "bottom",
          align: "center",
        },
      },
      {
        element: "[data-tour='webhook-test']",
        interactive: true,
        waitFor: "webhook_sent",
        popover: {
          title: "Send a Test Webhook",
          description:
            'Click "Simulate Front Webhook" below. It\u2019ll create a real ticket from the payload and trigger any matching rules.',
          side: "top",
          align: "center",
        },
      },
    ],
  },
]

const TOTAL_STEPS = TOUR.reduce((sum, page) => sum + page.steps.length, 0)

function globalOffset(pageIndex) {
  return TOUR.slice(0, pageIndex).reduce((sum, page) => sum + page.steps.length, 0)
}

const TourHook = {
  mounted() {
    this.driverInstance = null
    this.navigating = false
    this.waitingFor = null
    this.skipTimer = null
    this.currentPageIndex = 0
    this.currentLocalStep = 0
    this.resumeBanner = null

    const btn = this.el.querySelector("#start-tour-btn")
    if (btn) btn.addEventListener("click", () => this.runPage(0, 0))

    this.handleEvent("tour:action_complete", ({ action }) => {
      if (this.driverInstance && this.waitingFor === action) {
        this.waitingFor = null
        this.clearSkipTimer()
        setTimeout(() => {
          if (this.driverInstance) this.driverInstance.moveNext()
        }, 600)
      }
    })

    const state = this.loadState()
    if (state && state.interrupted) {
      this.showResumeBanner(state)
    } else if (state && state.active) {
      setTimeout(() => this.runPage(state.pageIndex, state.stepIndex), 300)
    } else if (window.location.search.includes("tour=1")) {
      setTimeout(() => this.runPage(0, 0), 500)
    } else if (!localStorage.getItem("supportdeck_toured")) {
      setTimeout(() => this.runPage(0, 0), 800)
    }
  },

  runPage(pageIndex, localStep) {
    this.removeResumeBanner()
    const page = TOUR[pageIndex]
    if (!page) return this.finish()

    this.currentPageIndex = pageIndex

    if (window.location.pathname !== page.path) {
      this.saveState({ pageIndex, stepIndex: localStep, active: true })
      this.navigating = true
      this.navigateTo(page.path)
      return
    }

    const offset = globalOffset(pageIndex)
    const isLastPage = pageIndex >= TOUR.length - 1
    const isFirstPage = pageIndex === 0

    const steps = page.steps
      .filter((s) => document.querySelector(s.element))
      .map((step, i) => ({
        ...step,
        popover: {
          ...step.popover,
          description: `${step.popover.description}<div class="tour-progress">${offset + i + 1} of ${TOTAL_STEPS}</div>`,
        },
      }))

    if (steps.length === 0) {
      return this.runPage(pageIndex + 1, 0)
    }

    const safeLocal = Math.min(localStep, steps.length - 1)

    this.driverInstance = driver({
      disableActiveInteraction: false,
      overlayColor: "rgba(0, 0, 0, 0.5)",
      stagePadding: 12,
      stageRadius: 8,
      popoverClass: "tour-popover",
      showProgress: false,
      steps,

      onHighlightStarted: (_element, step) => {
        this.clearSkipTimer()
        this.waitingFor = null
        this.currentLocalStep = this.driverInstance.getActiveIndex()

        requestAnimationFrame(() => {
          const popover = document.querySelector(".driver-popover")
          if (popover) {
            popover.classList.toggle("tour-interactive", !!step.interactive)
          }

          if (step.interactive) {
            this.waitingFor = step.waitFor
            this.startSkipTimer()
          } else {
            const active = document.querySelector(".driver-active-element")
            if (active) active.style.pointerEvents = "none"
          }
        })
      },

      onNextClick: () => {
        const idx = this.driverInstance.getActiveIndex()
        if (idx >= steps.length - 1) {
          this.driverInstance.destroy()
          this.driverInstance = null
          if (isLastPage) {
            this.finish()
          } else {
            this.runPage(pageIndex + 1, 0)
          }
        } else {
          this.driverInstance.moveNext()
        }
      },

      onPrevClick: () => {
        const idx = this.driverInstance.getActiveIndex()
        if (idx === 0) {
          this.driverInstance.destroy()
          this.driverInstance = null
          if (isFirstPage) {
            this.finish()
          } else {
            const prevPage = TOUR[pageIndex - 1]
            this.runPage(pageIndex - 1, prevPage.steps.length - 1)
          }
        } else {
          this.driverInstance.movePrevious()
        }
      },

      onCloseClick: () => {
        this.driverInstance.destroy()
        this.driverInstance = null
        this.finish()
      },
    })

    this.driverInstance.drive(safeLocal)
  },

  showResumeBanner(state) {
    this.removeResumeBanner()
    const offset = globalOffset(state.pageIndex) + state.stepIndex + 1

    const banner = document.createElement("div")
    banner.className = "tour-resume-banner"
    banner.innerHTML =
      `<span>Tour paused \u2014 step ${offset} of ${TOTAL_STEPS}</span>` +
      `<div class="tour-resume-actions">` +
      `<button class="tour-resume-continue">Continue</button>` +
      `<button class="tour-resume-stop">Stop Tour</button>` +
      `</div>`

    banner.querySelector(".tour-resume-continue").addEventListener("click", () => {
      this.removeResumeBanner()
      this.runPage(state.pageIndex, state.stepIndex)
    })

    banner.querySelector(".tour-resume-stop").addEventListener("click", () => {
      this.removeResumeBanner()
      this.finish()
    })

    document.body.appendChild(banner)
    this.resumeBanner = banner
  },

  removeResumeBanner() {
    if (this.resumeBanner) {
      this.resumeBanner.remove()
      this.resumeBanner = null
    }
  },

  startSkipTimer() {
    this.skipTimer = setTimeout(() => {
      const footer = document.querySelector(".driver-popover-footer")
      if (!footer || footer.querySelector(".tour-skip")) return

      const btn = document.createElement("button")
      btn.textContent = "Skip \u2192"
      btn.className = "tour-skip"
      btn.addEventListener("click", () => {
        if (this.driverInstance) this.driverInstance.moveNext()
      })
      footer.appendChild(btn)
    }, 8000)
  },

  clearSkipTimer() {
    if (this.skipTimer) {
      clearTimeout(this.skipTimer)
      this.skipTimer = null
    }
    const existing = document.querySelector(".tour-skip")
    if (existing) existing.remove()
  },

  saveState(state) {
    sessionStorage.setItem("tour_state", JSON.stringify(state))
  },

  loadState() {
    try {
      return JSON.parse(sessionStorage.getItem("tour_state"))
    } catch {
      return null
    }
  },

  clearState() {
    sessionStorage.removeItem("tour_state")
  },

  navigateTo(path) {
    const link = document.querySelector(`nav a[href="${path}"]`)
    if (link) link.click()
    else window.location.pathname = path
  },

  finish() {
    this.clearSkipTimer()
    this.clearState()
    this.removeResumeBanner()
    localStorage.setItem("supportdeck_toured", "true")
  },

  destroyed() {
    this.clearSkipTimer()

    if (this.navigating) {
      if (this.driverInstance) {
        this.driverInstance.destroy()
        this.driverInstance = null
      }
      return
    }

    if (this.driverInstance) {
      const step = this.driverInstance.getActiveIndex() || 0
      this.saveState({
        pageIndex: this.currentPageIndex,
        stepIndex: step,
        interrupted: true,
      })
      this.driverInstance.destroy()
      this.driverInstance = null
    }

    this.removeResumeBanner()
  },
}

export default TourHook
