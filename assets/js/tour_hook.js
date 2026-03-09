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
        popover: {
          title: "Create a Ticket",
          description:
            "Try creating one \u2014 it\u2019ll appear instantly via PubSub and get picked up by the AI triage worker and rule engine.",
          side: "bottom",
          align: "end",
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
        popover: {
          title: "Simulate Inbound Webhooks",
          description:
            "Send test payloads to Front, Slack, or Linear webhook endpoints. The worker parses them and creates or updates tickets, triggering rules along the way.",
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

    const btn = this.el.querySelector("#start-tour-btn")
    if (btn) btn.addEventListener("click", () => this.runPage(0, 0))

    const savedPage = sessionStorage.getItem("tour_page")
    const savedStep = sessionStorage.getItem("tour_step")
    if (savedPage !== null) {
      setTimeout(
        () => this.runPage(parseInt(savedPage), parseInt(savedStep || "0")),
        300,
      )
    } else if (window.location.search.includes("tour=1")) {
      setTimeout(() => this.runPage(0, 0), 500)
    } else if (!localStorage.getItem("supportdeck_toured")) {
      setTimeout(() => this.runPage(0, 0), 800)
    }
  },

  runPage(pageIndex, localStep) {
    const page = TOUR[pageIndex]
    if (!page) return this.finish()

    if (window.location.pathname !== page.path) {
      sessionStorage.setItem("tour_page", pageIndex.toString())
      sessionStorage.setItem("tour_step", localStep.toString())
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
      this.runPage(pageIndex + 1, 0)
      return
    }

    const safeLocal = Math.min(localStep, steps.length - 1)

    this.driverInstance = driver({
      disableActiveInteraction: true,
      overlayColor: "rgba(0, 0, 0, 0.5)",
      stagePadding: 12,
      stageRadius: 8,
      popoverClass: "tour-popover",
      showProgress: false,
      steps,
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

  navigateTo(path) {
    const link = document.querySelector(`nav a[href="${path}"]`)
    if (link) link.click()
    else window.location.pathname = path
  },

  finish() {
    sessionStorage.removeItem("tour_page")
    sessionStorage.removeItem("tour_step")
    localStorage.setItem("supportdeck_toured", "true")
  },

  destroyed() {
    if (this.driverInstance) {
      this.driverInstance.destroy()
      this.driverInstance = null
    }
    if (!this.navigating) {
      sessionStorage.removeItem("tour_page")
      sessionStorage.removeItem("tour_step")
    }
  },
}

export default TourHook
