const $ = (id) => document.getElementById(id);
let dashboard = null;
let snapshot = null;
let selectedGuide = "";
let attentionOnly = false;
const escapeHTML = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );
const setText = (id, value) => {
  const element = $(id);
  if (element) element.textContent = value ?? "—";
};
const formatDuration = (seconds) => {
  const days = Math.floor(seconds / 86400),
    hours = Math.floor((seconds % 86400) / 3600),
    minutes = Math.floor((seconds % 3600) / 60);
  return [days && days + "d", hours && hours + "h", minutes + "m"]
    .filter(Boolean)
    .join(" ");
};
function renderHealth() {
  const health = dashboard.health;
  $("health-orb").className = "health-orb " + health.status;
  setText(
    "health-status",
    health.status.charAt(0).toUpperCase() + health.status.slice(1),
  );
  setText("health-summary", health.summary);
  setText("health-passed", health.passed);
  setText("health-warnings", health.warnings);
  setText("health-critical", health.critical);
  setText(
    "health-time",
    "Evaluated " + new Date(health.evaluated_at).toLocaleTimeString(),
  );
  setText(
    "event-health",
    health.status.charAt(0).toUpperCase() + health.status.slice(1),
  );
  $("health-checks").innerHTML = health.checks
    .map(
      (check) =>
        '<article class="health-check ' +
        escapeHTML(check.status) +
        '"><span class="check-icon">' +
        (check.status === "passed"
          ? "✓"
          : check.status === "critical"
            ? "!"
            : "•") +
        "</span><strong>" +
        escapeHTML(check.name) +
        "</strong><p>" +
        escapeHTML(check.summary) +
        "</p><small>" +
        escapeHTML(check.evidence) +
        "</small></article>",
    )
    .join("");
}
function renderEvents() {
  const events = (dashboard.events || []).filter(
    (event) => !attentionOnly || event.severity !== "info",
  );
  $("event-list").innerHTML = events.length
    ? events
        .map(
          (event) =>
            '<article class="event-row ' +
            escapeHTML(event.severity) +
            '"><header><strong>' +
            escapeHTML(event.title) +
            "</strong><time>" +
            new Date(event.timestamp).toLocaleTimeString() +
            "</time></header><p>" +
            escapeHTML(event.detail) +
            "</p><small>" +
            escapeHTML(event.category.toUpperCase()) +
            "</small></article>",
        )
        .join("")
    : '<p class="event-empty">No matching events have b' +
      "een recorded during this boot.</p>";
  const latest = events[0] || dashboard.events?.[0];
  setText(
    "event-feature",
    latest
      ? latest.title + " — " + latest.detail
      : "Monitoring the board for hardware and kernel eve" + "nts\u2026",
  );
}
function renderCapabilities() {
  const capabilities = dashboard.capabilities || [];
  setText(
    "capability-count",
    capabilities.filter((item) => item.available).length + " AVAILABLE",
  );
  $("capability-list").innerHTML = capabilities
    .map(
      (item) =>
        '<article class="capability-card ' +
        (item.available ? "available" : "") +
        '"><span>' +
        escapeHTML(item.category.toUpperCase()) +
        "</span><strong>" +
        escapeHTML(item.name) +
        "</strong><small>" +
        escapeHTML(item.detail) +
        "</small></article>",
    )
    .join("");
}
function renderGuide() {
  const guides = dashboard.guides || [];
  if (!selectedGuide && guides.length) selectedGuide = guides[0].id;
  $("guide-list").innerHTML = guides
    .map(
      (guide) =>
        '<button type="button" data-guide="' +
        escapeHTML(guide.id) +
        '" class="' +
        (guide.id === selectedGuide ? "active" : "") +
        '">' +
        escapeHTML(guide.name) +
        "</button>",
    )
    .join("");
  document.querySelectorAll("[data-guide]").forEach((button) =>
    button.addEventListener("click", () => {
      selectedGuide = button.dataset.guide;
      renderGuide();
    }),
  );
  const guide = guides.find((item) => item.id === selectedGuide);
  if (!guide) return;
  $("guide-detail").innerHTML =
    "<h3>" +
    escapeHTML(guide.name) +
    "</h3><p>" +
    escapeHTML(guide.description) +
    "</p>" +
    guide.steps
      .map(
        (step) =>
          '<div class="guide-step ' +
          escapeHTML(step.status) +
          '"><i></i><strong>' +
          escapeHTML(step.name) +
          "</strong><small>" +
          escapeHTML(step.evidence) +
          "</small></div>",
      )
      .join("") +
    '<div class="guide-conclusion"><strong>Conclusion' +
    "</strong><p>" +
    escapeHTML(guide.conclusion) +
    "</p></div>";
}
function renderActions() {
  $("action-list").innerHTML = (dashboard.actions || [])
    .map(
      (action) =>
        '<article class="action-card"><strong>' +
        escapeHTML(action.name) +
        "</strong><p>" +
        escapeHTML(
          action.available ? action.description : action.unavailable_reason,
        ) +
        '</p><button type="button" data-action="' +
        escapeHTML(action.id) +
        '" ' +
        (action.available ? "" : "disabled") +
        ">" +
        (action.available ? "Run check" : "Unavailable") +
        "</button></article>",
    )
    .join("");
  document
    .querySelectorAll("[data-action]")
    .forEach((button) =>
      button.addEventListener("click", () =>
        runAction(button.dataset.action, button),
      ),
    );
}
async function runAction(id, button) {
  button.disabled = true;
  button.textContent = "Running…";
  try {
    const response = await fetch("/api/v1/diagnostic-run", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-VAR-Scope-Action": "diagnostic",
      },
      body: JSON.stringify({
        id,
      }),
    });
    if (!response.ok)
      throw new Error((await response.text()).trim() || "Diagnostic failed");
    const result = await response.json();
    $("action-result").classList.remove("hidden");
    $("action-result").innerHTML =
      "<strong>" +
      escapeHTML(result.summary) +
      "</strong><p>Status: " +
      escapeHTML(result.status) +
      " \xB7 " +
      result.duration_ms +
      " ms</p><ul>" +
      (result.checks || [])
        .map(
          (check) =>
            "<li>" +
            escapeHTML(check.name) +
            " \u2014 " +
            escapeHTML(check.status) +
            "" +
            (check.evidence ? " · " + escapeHTML(check.evidence) : "") +
            "</li>",
        )
        .join("") +
      "</ul>";
    await loadDiagnostics();
  } catch (error) {
    $("action-result").classList.remove("hidden");
    $("action-result").innerHTML =
      "<strong>Diagnostic could not run</strong><p>" +
      escapeHTML(error.message) +
      "</p>";
  } finally {
    button.disabled = false;
    button.textContent = "Run check";
  }
}
function renderEventMode() {
  if (!snapshot) return;
  const board = snapshot.board || {},
    metrics = snapshot.metrics || {},
    thermals = snapshot.thermals || [];
  setText("event-product-name", board.name || snapshot.system.model);
  setText("event-product-model", snapshot.system.model);
  const image = $("event-product-image");
  if (board.image_url) {
    image.src = board.image_url;
    image.alt = board.name || "Detected Variscite module";
    image.hidden = false;
  } else image.hidden = true;
  $("event-product-tags").innerHTML = [
    snapshot.system.architecture,
    board.soc,
    snapshot.bsp.distro_version,
  ]
    .filter(Boolean)
    .map((value) => "<span>" + escapeHTML(value) + "</span>")
    .join("");
  setText("event-cpu", Number(metrics.cpu_percent || 0).toFixed(0) + "%");
  setText(
    "event-memory",
    metrics.memory_total_bytes
      ? (
          (100 * metrics.memory_used_bytes) /
          metrics.memory_total_bytes
        ).toFixed(0) + "%"
      : "N/A",
  );
  const hottest = thermals.reduce(
    (best, item) => (item.celsius > (best?.celsius || -Infinity) ? item : best),
    null,
  );
  setText(
    "event-temperature",
    hottest ? Number(hottest.celsius).toFixed(1) + "°C" : "N/A",
  );
  setText("event-uptime", formatDuration(snapshot.system.uptime_seconds));
  setText(
    "event-access-url",
    location.origin.replace(/^http:/, "") + " · same local network",
  );
}
async function loadSnapshot() {
  try {
    const response = await fetch("/api/v1/snapshot", {
      cache: "no-store",
    });
    if (!response.ok) throw new Error("Snapshot unavailable");
    snapshot = await response.json();
    renderEventMode();
  } catch (error) {
    console.error(error);
  }
}
async function loadDiagnostics() {
  try {
    const response = await fetch("/api/v1/diagnostics", {
      cache: "no-store",
    });
    if (!response.ok) throw new Error("Diagnostics unavailable");
    dashboard = await response.json();
    renderHealth();
    renderEvents();
    renderCapabilities();
    renderGuide();
    renderActions();
    setText("connection", "Live updates");
  } catch (error) {
    setText("connection", "Unavailable");
    console.error(error);
  }
}
$("critical-only").addEventListener("change", (event) => {
  attentionOnly = event.target.checked;
  if (dashboard) renderEvents();
});
$("event-mode-open").addEventListener("click", async () => {
  await loadSnapshot();
  $("event-mode").showModal();
  document.documentElement.requestFullscreen?.().catch(() => {});
});
$("event-mode-close").addEventListener("click", () => {
  $("event-mode").close();
  if (document.fullscreenElement) document.exitFullscreen?.();
});
setInterval(() => setText("clock", new Date().toLocaleTimeString()), 1000);
setInterval(loadSnapshot, 2000);
setInterval(loadDiagnostics, 5000);
Promise.all([loadSnapshot(), loadDiagnostics()]);
