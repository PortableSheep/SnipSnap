// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            const offset = 60;
            const targetPosition = target.offsetTop - offset;
            window.scrollTo({
                top: targetPosition,
                behavior: 'smooth'
            });
        }
    });
});

// Add scroll class to nav
let lastScroll = 0;
const nav = document.querySelector('.nav');

window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;
    
    if (currentScroll > 0) {
        nav.style.boxShadow = '0 1px 3px rgba(0, 0, 0, 0.05)';
    } else {
        nav.style.boxShadow = 'none';
    }
    
    lastScroll = currentScroll;
});

// Theme toggle
(function () {
    const toggle = document.getElementById('theme-toggle');
    const root = document.documentElement;
    const storageKey = 'snipsnap-theme';

    function getSystemTheme() {
        return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }

    function getEffectiveTheme(preference) {
        if (preference === 'system') return getSystemTheme();
        return preference;
    }

    function applyTheme(preference) {
        if (preference === 'system') {
            root.removeAttribute('data-theme');
        } else {
            root.setAttribute('data-theme', preference);
        }
        toggle.textContent = getEffectiveTheme(preference) === 'dark' ? '☀️' : '🌙';
    }

    // Cycle: system → dark → light → system
    const cycle = { system: 'dark', dark: 'light', light: 'system' };

    toggle.addEventListener('click', () => {
        const current = localStorage.getItem(storageKey) || 'system';
        const next = cycle[current];
        localStorage.setItem(storageKey, next);
        applyTheme(next);
    });

    // React to system theme changes when in "system" mode
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        const pref = localStorage.getItem(storageKey) || 'system';
        if (pref === 'system') applyTheme('system');
    });

    // Initialize
    applyTheme(localStorage.getItem(storageKey) || 'system');
})();
