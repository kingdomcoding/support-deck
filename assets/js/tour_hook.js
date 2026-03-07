import { driver } from "driver.js"
import "driver.js/dist/driver.css"

const TOUR_STEPS = [
  {
    element: "[data-tour='dashboard']",
    popover: {
      title: "Dashboard",
      description: "Real-time overview of your support operations — open tickets, SLA breaches, active rules, and AI triage stats.",
      side: "right",
    },
  },
  {
    element: "[data-tour='tickets']",
    popover: {
      title: "Ticket Queue",
      description: "All support tickets with state machine transitions, search, filtering, and sortable columns.",
      side: "right",
    },
  },
  {
    element: "[data-tour='sla']",
    popover: {
      title: "SLA Monitor",
      description: "Tracks response and resolution deadlines. Breaching tickets trigger AshOban escalation workers.",
      side: "right",
    },
  },
  {
    element: "[data-tour='ai']",
    popover: {
      title: "AI Triage",
      description: "Automated ticket classification powered by LLM prompts. Tracks confidence scores and category predictions.",
      side: "right",
    },
  },
  {
    element: "[data-tour='rules']",
    popover: {
      title: "Automation Rules",
      description: "Event-driven rule engine — match conditions on ticket fields and dispatch Oban worker actions.",
      side: "right",
    },
  },
  {
    element: "[data-tour='integrations']",
    popover: {
      title: "Integration Health",
      description: "Circuit breaker status for Front, Slack, and Linear. Auto-trips after consecutive failures, recovers with half-open probes.",
      side: "right",
    },
  },
  {
    element: "[data-tour='settings']",
    popover: {
      title: "Settings & Credentials",
      description: "Encrypted credential vault using AES-256-GCM. API keys are cached in ETS via a GenServer resolver.",
      side: "right",
    },
  },
  {
    element: "[data-tour='simulator']",
    popover: {
      title: "Simulator",
      description: "Test the full pipeline — create tickets, fire webhooks, run AI triage, and trip circuit breakers.",
      side: "right",
    },
  },
]

const TourHook = {
  mounted() {
    this.driverInstance = null

    const btn = this.el.querySelector("#start-tour-btn")
    if (btn) {
      btn.addEventListener("click", () => this.startTour())
    }

    if (window.location.search.includes("tour=1")) {
      setTimeout(() => this.startTour(), 500)
    } else if (!localStorage.getItem("supportdeck_toured")) {
      setTimeout(() => this.startTour(), 1000)
    }
  },

  startTour() {
    if (this.driverInstance) {
      this.driverInstance.destroy()
    }

    this.driverInstance = driver({
      showProgress: true,
      animate: true,
      overlayColor: "rgba(0, 0, 0, 0.5)",
      stagePadding: 8,
      stageRadius: 8,
      popoverClass: "driverjs-theme",
      steps: TOUR_STEPS.filter((step) => document.querySelector(step.element)),
      onDestroyed: () => {
        localStorage.setItem("supportdeck_toured", "true")
      },
    })

    this.driverInstance.drive()
  },

  destroyed() {
    if (this.driverInstance) {
      this.driverInstance.destroy()
    }
  },
}

export default TourHook
