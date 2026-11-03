for (const toggle of document.querySelectorAll(".toggle-password")) {
  toggle.addEventListener("click", () => {
    const input = toggle.parentElement?.querySelector('input[type="password"], input[type="text"]');
    if (!input) return;
    input.type = input.type === "password" ? "text" : "password";
    toggle.classList.toggle("ri-eye-off-line", input.type === "password");
    toggle.classList.toggle("ri-eye-line", input.type === "text");
  });
}