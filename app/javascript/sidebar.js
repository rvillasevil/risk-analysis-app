document.addEventListener('turbo:load', () => {
  const sidebar = document.getElementById('dr-sidebar');
  const toggle  = document.getElementById('sidebarToggle');

  if (!sidebar || !toggle) return;

  toggle.addEventListener('click', () => {
    sidebar.classList.toggle('show');
    // recuerda el estado en una cookie opcional
    document.cookie = `sidebar=${sidebar.classList.contains('show') ? 'open' : 'closed'}; path=/; SameSite=Lax`;
  });
});
