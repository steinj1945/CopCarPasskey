const BASE = "/api";

const state = {
  page: 1,
  totalPages: 1,
  currentTab: "keys",
};

function token() {
  return localStorage.getItem("token");
}

function authHeaders() {
  const t = token();
  return t
    ? { Authorization: `Bearer ${t}`, "Content-Type": "application/json" }
    : { "Content-Type": "application/json" };
}

async function api(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: authHeaders(),
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `HTTP ${res.status}`);
  }

  if (res.status === 204) {
    return null;
  }

  const contentType = res.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return res.json();
  }

  return res.text();
}

function fmtDate(value) {
  const date = new Date(value);
  return date.toLocaleString();
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function showLogin(showError = "") {
  document.getElementById("view-login").classList.remove("hidden");
  document.getElementById("view-app").classList.add("hidden");

  const el = document.getElementById("login-error");
  el.textContent = showError;
  el.classList.toggle("hidden", !showError);
}

function showApp() {
  document.getElementById("view-login").classList.add("hidden");
  document.getElementById("view-app").classList.remove("hidden");
  setTab(state.currentTab);
}

function setTab(tab) {
  state.currentTab = tab;

  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === tab);
  });

  document.getElementById("tab-keys").classList.toggle("hidden", tab !== "keys");
  document.getElementById("tab-logs").classList.toggle("hidden", tab !== "logs");

  if (tab === "keys") {
    loadKeys();
  } else {
    loadLogs();
  }
}

async function loadKeys() {
  const body = document.getElementById("keys-body");

  try {
    const keys = await api("GET", "/keys");

    if (!keys.length) {
      body.innerHTML = '<tr><td colspan="5" class="muted">No keys yet</td></tr>';
      return;
    }

    body.innerHTML = keys
      .map((k) => {
        const status = k.isActive
          ? '<span class="badge-active">Active</span>'
          : '<span class="badge-revoked">Revoked</span>';

        const action = k.isActive
          ? `<button class="link-danger" data-revoke-id="${k.id}">Revoke</button>`
          : "";

        return `
<tr>
  <td>${escapeHtml(k.label)}</td>
  <td class="mono">...${escapeHtml(k.secretHint)}</td>
  <td>${fmtDate(k.createdAt)}</td>
  <td>${status}</td>
  <td>${action}</td>
</tr>`;
      })
      .join("");

    document.querySelectorAll("[data-revoke-id]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = Number(btn.dataset.revokeId);
        if (!confirm("Revoke this key? The device will no longer be able to unlock.")) {
          return;
        }

        await api("DELETE", `/keys/${id}`);
        await loadKeys();
      });
    });
  } catch (err) {
    if (`${err}`.includes("401")) {
      localStorage.removeItem("token");
      showLogin("Session expired. Please sign in again.");
      return;
    }

    body.innerHTML = `<tr><td colspan="5" class="error">Failed to load keys: ${escapeHtml(`${err}`)}</td></tr>`;
  }
}

async function loadLogs() {
  const body = document.getElementById("logs-body");

  try {
    const page = await api("GET", `/logs?page=${state.page}&pageSize=50`);
    state.totalPages = Math.max(1, Math.ceil(page.total / page.pageSize));

    if (!page.items.length) {
      body.innerHTML = '<tr><td colspan="4" class="muted">No events yet</td></tr>';
    } else {
      body.innerHTML = page.items
        .map((entry) => `
<tr>
  <td>${fmtDate(entry.occurredAt)}</td>
  <td>${escapeHtml(entry.event)}</td>
  <td>${escapeHtml(entry.keyLabel || "-")}</td>
  <td>${escapeHtml(entry.deviceLabel || "-")}</td>
</tr>`)
        .join("");
    }

    document.getElementById("page-info").textContent = `${state.page} / ${state.totalPages}`;
    document.getElementById("prev-page").disabled = state.page <= 1;
    document.getElementById("next-page").disabled = state.page >= state.totalPages;
  } catch (err) {
    body.innerHTML = `<tr><td colspan="4" class="error">Failed to load logs: ${escapeHtml(`${err}`)}</td></tr>`;
  }
}

async function showNewKeyModal(data) {
  const modal = document.getElementById("qr-modal");
  const title = document.getElementById("qr-title");
  const link = document.getElementById("qr-link");
  const secret = document.getElementById("qr-secret");
  const inlineQr = document.getElementById("qr-inline");

  const enrollUrl = `CopCarpasskey://enroll?secret=${encodeURIComponent(data.secret)}&label=${encodeURIComponent(data.label)}`;
  title.textContent = `Enroll: ${data.label}`;
  link.href = enrollUrl;
  link.textContent = enrollUrl;
  secret.textContent = data.secret;

  inlineQr.textContent = "Generating QR...";
  try {
    const svg = await api("POST", "/qr", { text: enrollUrl });
    inlineQr.innerHTML = svg;
  } catch {
    inlineQr.textContent = "Failed to generate QR. Use the enrollment link below.";
  }

  modal.classList.remove("hidden");
}

function wireEvents() {
  document.getElementById("login-form").addEventListener("submit", async (e) => {
    e.preventDefault();

    const username = document.getElementById("username").value.trim();
    const password = document.getElementById("password").value;

    try {
      const res = await api("POST", "/auth/login", { username, password });
      localStorage.setItem("token", res.token);
      showApp();
      await loadKeys();
    } catch {
      showLogin("Invalid username or password");
    }
  });

  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.addEventListener("click", () => setTab(btn.dataset.tab));
  });

  document.getElementById("signout").addEventListener("click", () => {
    localStorage.removeItem("token");
    showLogin();
  });

  document.getElementById("create-key-form").addEventListener("submit", async (e) => {
    e.preventDefault();

    const labelInput = document.getElementById("new-key-label");
    const label = labelInput.value.trim();
    if (!label) {
      return;
    }

    const issueButton = document.getElementById("issue-key");
    issueButton.disabled = true;

    try {
      const result = await api("POST", "/keys", { label });
      labelInput.value = "";
      await showNewKeyModal(result);
      await loadKeys();
    } finally {
      issueButton.disabled = false;
    }
  });

  document.getElementById("close-modal").addEventListener("click", () => {
    document.getElementById("qr-modal").classList.add("hidden");
  });

  document.getElementById("prev-page").addEventListener("click", async () => {
    state.page = Math.max(1, state.page - 1);
    await loadLogs();
  });

  document.getElementById("next-page").addEventListener("click", async () => {
    state.page = Math.min(state.totalPages, state.page + 1);
    await loadLogs();
  });
}

function init() {
  wireEvents();

  if (token()) {
    showApp();
    loadKeys();
  } else {
    showLogin();
  }
}

init();
