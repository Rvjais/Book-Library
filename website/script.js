/* ==========================================================================
   LibReady Website — Interactive Features & Handcrafted Behaviors
   ========================================================================== */

(function () {
  'use strict';

  /* ── 1. Light / Dark / System Theme Toggle ────────────────────────────── */
  const THEME_KEY = 'libready-theme';
  const MODES = ['light', 'dark', 'system'];
  let modeIndex = 0;

  const root   = document.documentElement;
  const toggle = document.getElementById('theme-toggle');
  const label  = toggle ? toggle.querySelector('.theme-toggle__label') : null;
  const LABELS = { light: 'Light', dark: 'Dark', system: 'Auto' };

  function resolveTheme(mode) {
    if (mode === 'system') {
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }
    return mode;
  }

  function applyTheme(mode) {
    const resolved = resolveTheme(mode);
    root.setAttribute('data-theme', resolved);
    root.style.colorScheme = resolved;

    const metaTheme = document.querySelector('meta[name="theme-color"]');
    if (metaTheme) {
      metaTheme.content = resolved === 'dark' ? '#130F0C' : '#F7EFE3';
    }

    if (toggle) {
      toggle.querySelectorAll('.theme-toggle__icon').forEach(i => i.style.display = 'none');
      const iconClass = mode === 'system' ? 'theme-toggle__system' : (mode === 'dark' ? 'theme-toggle__moon' : 'theme-toggle__sun');
      const icon = toggle.querySelector('.' + iconClass);
      if (icon) icon.style.display = 'block';
      if (label) label.textContent = LABELS[mode];
    }

    try { localStorage.setItem(THEME_KEY, mode); } catch (_) {}
  }

  function cycleTheme() {
    modeIndex = (modeIndex + 1) % MODES.length;
    applyTheme(MODES[modeIndex]);
  }

  (function initTheme() {
    let saved;
    try { saved = localStorage.getItem(THEME_KEY); } catch (_) {}
    if (!saved || !MODES.includes(saved)) saved = 'light';
    modeIndex = MODES.indexOf(saved);
    applyTheme(saved);

    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (MODES[modeIndex] === 'system') applyTheme('system');
    });

    if (toggle) toggle.addEventListener('click', cycleTheme);
  })();

  /* ── 2. Mobile Nav Drawer & Backdrop UX ──────────────────────────────── */
  const hamburger       = document.getElementById('hamburger');
  const nav             = document.getElementById('nav');
  const navBackdrop     = document.getElementById('nav-backdrop');
  const navDrawerClose  = document.getElementById('nav-drawer-close');

  function openNav() {
    if (!nav) return;
    hamburger.setAttribute('aria-expanded', 'true');
    nav.classList.add('open');
    if (navBackdrop) navBackdrop.classList.add('open');
    document.body.classList.add('nav-locked');
  }

  function closeNav() {
    if (!nav) return;
    hamburger.setAttribute('aria-expanded', 'false');
    nav.classList.remove('open');
    if (navBackdrop) navBackdrop.classList.remove('open');
    document.body.classList.remove('nav-locked');
  }

  if (hamburger && nav) {
    hamburger.addEventListener('click', () => {
      const isOpen = nav.classList.contains('open');
      if (isOpen) closeNav();
      else openNav();
    });

    if (navDrawerClose) navDrawerClose.addEventListener('click', closeNav);
    if (navBackdrop) navBackdrop.addEventListener('click', closeNav);

    // Close on any link click
    nav.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', closeNav);
    });

    // Close on Escape key
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && nav.classList.contains('open')) {
        closeNav();
      }
    });
  }

  /* ── 3. Active Nav Link on Scroll ─────────────────────────────────────── */
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav__list a');

  function highlightNav() {
    const y = window.scrollY;
    let current = null;
    sections.forEach(s => {
      if (y >= s.offsetTop - 160 && y < s.offsetTop + s.offsetHeight - 160) {
        current = s.id;
      }
    });
    navLinks.forEach(a => {
      a.classList.toggle('active', a.getAttribute('href') === '#' + current);
    });
  }
  window.addEventListener('scroll', highlightNav, { passive: true });
  highlightNav();

  /* ── 4. Sticky Header Shadow ──────────────────────────────────────────── */
  const navbar = document.getElementById('navbar');
  if (navbar) {
    window.addEventListener('scroll', () => {
      navbar.classList.toggle('scrolled', window.scrollY > 40);
    }, { passive: true });
  }

  /* ── 5. Gallery Category Filter & Load More ───────────────────────────── */
  const filterPills   = document.querySelectorAll('.filter-pill');
  const galleryCards  = document.querySelectorAll('.gallery-card');
  const loadMoreBtn   = document.getElementById('load-more-btn');
  const loadMoreText  = loadMoreBtn ? loadMoreBtn.querySelector('.load-more-text') : null;
  const initialHiddenCards = document.querySelectorAll('.gallery-card--hidden');

  let isGalleryExpanded = false;

  function updateGalleryDisplay(category) {
    if (category === 'all') {
      if (loadMoreBtn) loadMoreBtn.style.display = 'inline-flex';
      galleryCards.forEach((card, index) => {
        if (!isGalleryExpanded && index >= 6) {
          card.classList.add('gallery-card--hidden');
          card.style.display = 'none';
        } else {
          card.classList.remove('gallery-card--hidden');
          card.style.display = '';
          card.classList.add('visible');
        }
      });
    } else {
      if (loadMoreBtn) loadMoreBtn.style.display = 'none';
      galleryCards.forEach(card => {
        const cardCat = card.getAttribute('data-category');
        if (cardCat === category) {
          card.classList.remove('gallery-card--hidden');
          card.style.display = '';
          card.classList.add('visible');
        } else {
          card.style.display = 'none';
        }
      });
    }
  }

  filterPills.forEach(pill => {
    pill.addEventListener('click', () => {
      const category = pill.getAttribute('data-filter');
      filterPills.forEach(p => {
        p.classList.remove('filter-pill--active');
        p.setAttribute('aria-selected', 'false');
      });
      pill.classList.add('filter-pill--active');
      pill.setAttribute('aria-selected', 'true');
      updateGalleryDisplay(category);
    });
  });

  if (loadMoreBtn) {
    loadMoreBtn.addEventListener('click', () => {
      isGalleryExpanded = !isGalleryExpanded;
      loadMoreBtn.setAttribute('aria-expanded', String(isGalleryExpanded));
      loadMoreBtn.classList.toggle('expanded', isGalleryExpanded);

      if (loadMoreText) {
        loadMoreText.textContent = isGalleryExpanded ? 'Show Less Screenshots' : 'Load More Screenshots (6 remaining)';
      }

      const activePill = document.querySelector('.filter-pill--active');
      const currentCat = activePill ? activePill.getAttribute('data-filter') : 'all';
      updateGalleryDisplay(currentCat);

      if (!isGalleryExpanded) {
        const screensSection = document.getElementById('screens');
        if (screensSection) screensSection.scrollIntoView({ behavior: 'smooth' });
      }
    });
  }

  /* ── 6. Screenshot Lightbox Modal ─────────────────────────────────────── */
  const lightbox        = document.getElementById('lightbox');
  const lightboxOverlay = document.getElementById('lightbox-overlay');
  const lightboxClose   = document.getElementById('lightbox-close');
  const lightboxImg     = document.getElementById('lightbox-img');
  const lightboxTitle   = document.getElementById('lightbox-title');
  const lightboxDesc    = document.getElementById('lightbox-desc');

  function openLightbox(src, title, desc) {
    if (!lightbox) return;
    lightboxImg.src = src;
    lightboxImg.alt = title;
    lightboxTitle.textContent = title;
    lightboxDesc.textContent = desc;
    lightbox.removeAttribute('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    if (!lightbox) return;
    lightbox.setAttribute('hidden', '');
    lightboxImg.src = '';
    document.body.style.overflow = '';
  }

  document.querySelectorAll('.gallery-card__device').forEach(device => {
    device.addEventListener('click', () => {
      const src   = device.getAttribute('data-src');
      const title = device.getAttribute('data-title');
      const desc  = device.getAttribute('data-desc');
      if (src) openLightbox(src, title, desc);
    });
  });

  if (lightboxOverlay) lightboxOverlay.addEventListener('click', closeLightbox);
  if (lightboxClose) lightboxClose.addEventListener('click', closeLightbox);
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && lightbox && !lightbox.hasAttribute('hidden')) {
      closeLightbox();
    }
  });

  /* ── 7. Interactive Theme & Typography Simulator ──────────────────────── */
  const simPage         = document.getElementById('sim-page');
  const simBody         = document.getElementById('sim-body');
  const themeSwatches   = document.querySelectorAll('.btn-swatch');
  const textureBtns     = document.querySelectorAll('.btn-texture');
  const fontSizeSlider  = document.getElementById('font-size-slider');
  const fontSizeVal     = document.getElementById('font-size-val');
  const lineHeightSlider= document.getElementById('line-height-slider');
  const lineHeightVal   = document.getElementById('line-height-val');
  const justifyToggle   = document.getElementById('justify-toggle');

  if (simPage) {
    // Theme Switcher
    themeSwatches.forEach(btn => {
      btn.addEventListener('click', () => {
        const theme = btn.getAttribute('data-theme');
        themeSwatches.forEach(b => b.classList.remove('btn-swatch--active'));
        btn.classList.add('btn-swatch--active');

        simPage.classList.remove('sim-page--paper', 'sim-page--sepia', 'sim-page--night', 'sim-page--black');
        simPage.classList.add('sim-page--' + theme);
      });
    });

    // Texture Switcher
    textureBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const texture = btn.getAttribute('data-texture');
        textureBtns.forEach(b => b.classList.remove('btn-texture--active'));
        btn.classList.add('btn-texture--active');

        simPage.classList.remove('sim-texture--smooth', 'sim-texture--linen', 'sim-texture--cloth');
        simPage.classList.add('sim-texture--' + texture);
      });
    });

    // Font Size Slider
    if (fontSizeSlider && fontSizeVal && simBody) {
      fontSizeSlider.addEventListener('input', () => {
        const size = fontSizeSlider.value;
        fontSizeVal.textContent = size + 'px';
        simBody.style.fontSize = size + 'px';
      });
    }

    // Line Height Slider
    if (lineHeightSlider && lineHeightVal && simBody) {
      lineHeightSlider.addEventListener('input', () => {
        const lh = lineHeightSlider.value;
        lineHeightVal.textContent = lh;
        simBody.style.lineHeight = lh;
      });
    }

    // Justify Text Toggle
    if (justifyToggle && simBody) {
      justifyToggle.addEventListener('change', () => {
        simBody.style.textAlign = justifyToggle.checked ? 'justify' : 'left';
      });
    }
  }

  /* ── 8. Scroll Reveal Animations ──────────────────────────────────────── */
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -40px 0px' });

    document.querySelectorAll('.reveal').forEach(el => observer.observe(el));
  } else {
    document.querySelectorAll('.reveal').forEach(el => el.classList.add('visible'));
  }

})();
