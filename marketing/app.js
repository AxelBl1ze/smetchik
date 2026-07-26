const menuButton = document.querySelector(".menu-button");
const navLinks = document.querySelector(".nav-links");

menuButton?.addEventListener("click", () => {
  const opened = navLinks.classList.toggle("is-open");
  menuButton.setAttribute("aria-expanded", String(opened));
});

navLinks?.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => {
    navLinks.classList.remove("is-open");
    menuButton?.setAttribute("aria-expanded", "false");
  });
});

const tabs = document.querySelectorAll("[data-product-tab]");
const screens = document.querySelectorAll("[data-product-screen]");
const scenarioCopy = {
  estimate: {
    number: "01",
    title: "Смета собрана",
    copy: "Работы, клиент и итог уже на месте.",
    state: "3–5 мин",
  },
  approval: {
    number: "02",
    title: "Клиент подтвердил",
    copy: "Подпись, время и версия зафиксированы.",
    state: "PDF готов",
  },
  object: {
    number: "03",
    title: "Объект под контролем",
    copy: "Поступления и затраты видны в одном месте.",
    state: "233 600 ₽",
  },
};

const showScenario = (target) => {
  const scenario = scenarioCopy[target];
  if (!scenario) return;

  tabs.forEach((item) => {
    const active = item.dataset.productTab === target;
    item.classList.toggle("is-active", active);
    item.setAttribute("aria-selected", String(active));
  });

  screens.forEach((screen) => {
    const active = screen.dataset.productScreen === target;
    screen.hidden = !active;
    screen.classList.toggle("is-active", active);
  });

  document.querySelector("[data-scenario-number]").textContent = scenario.number;
  document.querySelector("[data-scenario-title]").textContent = scenario.title;
  document.querySelector("[data-scenario-copy]").textContent = scenario.copy;
  document.querySelector("[data-scenario-state]").textContent = scenario.state;
};

tabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    showScenario(tab.dataset.productTab);
  });
});

const proofContent = {
  version: "Сохраняется именно та версия сметы, которую видел клиент.",
  signature: "Подпись клиента, дата и время остаются в документе.",
  package: "PDF и служебные данные можно выгрузить одним пакетом доказательств.",
};

document.querySelectorAll("[data-proof]").forEach((button) => {
  button.addEventListener("click", () => {
    const target = button.dataset.proof;
    document.querySelectorAll("[data-proof]").forEach((item) => {
      const active = item === button;
      item.classList.toggle("is-active", active);
      item.setAttribute("aria-selected", String(active));
    });
    document.querySelector("[data-proof-copy]").textContent = proofContent[target];
  });
});

document.querySelectorAll("[data-copy-promo]").forEach((button) => {
  button.addEventListener("click", async () => {
    const code = button.dataset.copyPromo;
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code);
      const previous = button.innerHTML;
      button.textContent = "Скопировано";
      window.setTimeout(() => {
        button.innerHTML = previous;
      }, 1600);
    } catch {
      window.prompt("Скопируйте промокод", code);
    }
  });
});

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  },
  { threshold: 0.12 },
);

document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));
document.querySelector("#year").textContent = new Date().getFullYear();
