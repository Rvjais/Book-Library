/* ==========================================================================
   LibReady website behaviour
   - Theme toggle (light / dark / system) matching the Flutter app
   - Mobile nav menu
   - Active nav link on scroll
   - Download link handling
   ========================================================================== */

(function () {
  const THEME_KEY = 'libready-theme';
  const themes = ['light', 'dark', 'system'];
  let themeIndex = 0;

  const html = document.documentElement;
  const toggleBtn = document.getElementById('theme-toggle');
  const toggleText = toggleBtn.querySelector('.toggle-text');
  const toggleIcon = toggleBtn.querySelector('.toggle-icon');

  const labels = { light: 'Light', dark: 'Dark', system: 'System' };
  const icons = { light: '☀️', dark: '🌙', system: '🖥️' };

  // ---- Theme system ----
  function resolveTheme(theme) {
    if (theme === 'system') {
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }
    return theme;
  }

  function applyTheme(theme) {
    const resolved = resolveTheme(theme);
    html.setAttribute('data-theme', resolved);
    html.style.colorScheme = resolved;

    const current = themes[themeIndex];
    toggleText.textContent = labels[current];
    toggleIcon.textContent = icons[current];

    // Persist choice
    try { localStorage.setItem(THEME_KEY, theme); } catch (e) {}
  }

  function nextTheme() {
    themeIndex = (themeIndex + 1) % themes.length;
    applyTheme(themes[themeIndex]);
  }

  // Load saved theme or default to light
  (function initTheme() {
    let saved = null;
    try { saved = localStorage.getItem(THEME_KEY); } catch (e) {}
    if (!saved || !themes.includes(saved)) saved = 'light';
    themeIndex = themes.indexOf(saved);
    applyTheme(saved);

    // Re-resolve when system preference changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (themes[themeIndex] === 'system') applyTheme('system');
    });

    toggleBtn.addEventListener('click', nextTheme);
  })();

  // ---- Mobile nav ----
  const navMenu = document.getElementById('nav-menu');
  const nav = document.getElementById('nav');
  const header = document.getElementById('header');

  navMenu.addEventListener('click', () => {
    const open = navMenu.getAttribute('aria-expanded') === 'true';
    navMenu.setAttribute('aria-expanded', String(!open));
    nav.classList.toggle('open');
  });

  // Close mobile menu when clicking a link
  document.querySelectorAll('.nav-list a').forEach((link) => {
    link.addEventListener('click', () => {
      navMenu.setAttribute('aria-expanded', 'false');
      nav.classList.remove('open');
    });
  });

  // ---- Active nav link on scroll ----
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav-list a');

  function onScroll() {
    const scrollY = window.pageYOffset;
    let current = null;

    sections.forEach((section) => {
      const sectionTop = section.offsetTop - 120;
      const sectionBottom = sectionTop + section.offsetHeight;
      if (scrollY >= sectionTop && scrollY < sectionBottom) {
        current = section.getAttribute('id');
      }
    });

    navLinks.forEach((link) => {
      link.classList.toggle('active', link.getAttribute('href') === '#' + current);
    });
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // ---- Header scroll effect ----
  let lastScroll = 0;
  window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;
    if (currentScroll > 60) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
    lastScroll = currentScroll;
  }, { passive: true });

  // ---- Download handling ----
  const apkBtn = document.getElementById('apk-download');
  const appstoreBtn = document.getElementById('appstore-download');

  if (apkBtn) {
    apkBtn.addEventListener('click', (e) => {
      const href = apkBtn.getAttribute('href');
      if (!href || href === '#' || href.includes('releases/latest')) {
        e.preventDefault();
        const confirmDownload = confirm(
          'The APK will be provided via the GitHub Releases page.\n\n' +
          'To get the app now:\n1. Build it with "flutter build apk --release"\n2. Upload the APK to a GitHub Release\n3. Paste the release URL here'
        );
        if (confirmDownload) {
          window.location.href = 'https://github.com/Rvjais/Book-Library/releases';
        }
      }
    });
  }

  if (appstoreBtn) {
    appstoreBtn.style.opacity = '0.7';
    appstoreBtn.style.cursor = 'not-allowed';
    appstoreBtn.addEventListener('click', (e) => {
      e.preventDefault();
      alert('The iOS App Store listing is being prepared.\n\nIn the meantime, build for iOS with:\nflutter build ios\nThen open ios/Runner.xcworkspace in Xcode.');
    });
  }

  // ---- Smooth reveal for feature cards ----
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('revealed');
        }
      });
    },
    { threshold: 0.12, rootMargin: '0px 0px -60px 0px' }
  );

  document.querySelectorAll('.feature-card, .theme-card, .step').forEach((el) => {
    observer.observe(el);
  });
})();
