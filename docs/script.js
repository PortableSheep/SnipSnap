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
