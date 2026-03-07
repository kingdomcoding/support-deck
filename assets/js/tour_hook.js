import { driver } from "driver.js"
import "driver.js/dist/driver.css"

const TOUR_STEPS = [
  {
    path: "/",
    element: "[data-tour='dashboard']",
    popover: {
      title: "Dashboard",
      description:
        "Real-time overview of open tickets, SLA breaches, active rules, and AI triage stats.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/tickets",
    element: "[data-tour='tickets']",
    popover: {
      title: "Ticket Queue",
      description:
        "Full state-machine lifecycle with search, filtering, sortable columns, and inline transitions.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/sla",
    element: "[data-tour='sla']",
    popover: {
      title: "SLA Monitor",
      description:
        "Tracks response and resolution deadlines. Breaching tickets trigger AshOban escalation workers.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/ai",
    element: "[data-tour='ai']",
    popover: {
      title: "AI Triage",
      description:
        "Automated ticket classification powered by LLM prompts. Tracks confidence scores and category predictions.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/rules",
    element: "[data-tour='rules']",
    popover: {
      title: "Automation Rules",
      description:
        "Event-driven rule engine \u2014 match conditions on ticket fields and dispatch Oban worker actions.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/integrations",
    element: "[data-tour='integrations']",
    popover: {
      title: "Integration Health",
      description:
        "Circuit breaker status for Front, Slack, and Linear. Auto-trips after consecutive failures, recovers with half-open probes.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/settings",
    element: "[data-tour='settings']",
    popover: {
      title: "Settings & Credentials",
      description:
        "Encrypted credential vault using AES-256-GCM. API keys are cached in ETS via a GenServer resolver.",
      side: "right",
      align: "start",
    },
  },
  {
    path: "/simulator",
    element: "[data-tour='simulator']",
    popover: {
      title: "Simulator",
      description:
        "Test the full pipeline \u2014 create tickets, fire webhooks, run AI triage, and trip circuit breakers.",
      side: "right",
      align: "start",
    },
  },
]

const TourHook = {
  mounted() {
    this.driverInstance = null
    this.navigating = false

    const btn = this.el.querySelector("#start-tour-btn")
    if (btn) btn.addEventListener("click", () => this.runStep(0))

    const resumeStep = sessionStorage.getItem("tour_step")
    if (resumeStep !== null) {
      setTimeout(() => this.runStep(parseInt(resumeStep)), 300)
    } else if (window.location.search.includes("tour=1")) {
      setTimeout(() => this.runStep(0), 500)
    } else if (!localStorage.getItem("supportdeck_toured")) {
      setTimeout(() => this.runStep(0), 800)
    }
  },

  runStep(index) {
    const step = TOUR_STEPS[index]
    if (!step) return this.finish()

    if (window.location.pathname !== step.path) {
      sessionStorage.setItem("tour_step", index.toString())
      this.navigating = true
      this.navigateTo(step.path)
      return
    }

    const total = TOUR_STEPS.length
    const isLast = index >= total - 1
    const isFirst = index === 0

    this.driverInstance = driver({
      disableActiveInteraction: true,
      overlayColor: "rgba(0, 0, 0, 0.55)",
      stagePadding: 10,
      stageRadius: 8,
      popoverClass: "tour-popover",
      steps: [
        {
          element: step.element,
          popover: {
            ...step.popover,
            description: `${step.popover.description}<div class="tour-progress">${index + 1} of ${total}</div>`,
          },
        },
      ],
      nextBtnText: isLast ? "Finish" : "Next \u2192",
      prevBtnText: isFirst ? "Skip" : "\u2190 Back",
      onNextClick: () => {
        this.driverInstance.destroy()
        this.driverInstance = null
        isLast ? this.finish() : this.runStep(index + 1)
      },
      onPrevClick: () => {
        this.driverInstance.destroy()
        this.driverInstance = null
        isFirst ? this.finish() : this.runStep(index - 1)
      },
      onCloseClick: () => {
        this.driverInstance.destroy()
        this.driverInstance = null
        this.finish()
      },
    })

    this.driverInstance.drive()
  },

  navigateTo(path) {
    const link = document.querySelector(`nav a[href="${path}"]`)
    if (link) link.click()
    else window.location.pathname = path
  },

  finish() {
    sessionStorage.removeItem("tour_step")
    localStorage.setItem("supportdeck_toured", "true")
  },

  destroyed() {
    if (this.driverInstance) {
      this.driverInstance.destroy()
      this.driverInstance = null
    }
    if (!this.navigating) {
      sessionStorage.removeItem("tour_step")
    }
  },
}

export default TourHook
