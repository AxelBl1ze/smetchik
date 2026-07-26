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

tabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    const target = tab.dataset.productTab;
    tabs.forEach((item) => {
      const active = item === tab;
      item.classList.toggle("is-active", active);
      item.setAttribute("aria-selected", String(active));
    });
    screens.forEach((screen) => {
      const active = screen.dataset.productScreen === target;
      screen.hidden = !active;
      screen.classList.toggle("is-active", active);
    });
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
