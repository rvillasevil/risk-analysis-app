document.addEventListener('turbo:load', () => {
  const sidebar = document.getElementById('dr-sidebar');
  const toggle  = document.getElementById('sidebarToggle');

  if (!sidebar || !toggle) return;

  const setSidebarCookie = (isOpen) => {
    const maxAge = 60 * 60 * 24 * 30; // 30 days
    document.cookie = `sidebar=${isOpen ? 'open' : 'closed'}; path=/; max-age=${maxAge}; SameSite=Lax`;
  };

  const cookieMatch = document.cookie.split('; ').find(c => c.startsWith('sidebar='));
  const cookieValue = cookieMatch ? cookieMatch.split('=')[1] : null;
  if (cookieValue === 'open') sidebar.classList.add('show');  
  
  toggle.addEventListener('click', () => {
    sidebar.classList.toggle('show');
    // recuerda el estado en una cookie opcional
    setSidebarCookie(sidebar.classList.contains('show'));
  });
});
