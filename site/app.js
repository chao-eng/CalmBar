/**
 * CalmBar Official Website - Interactive Scripts
 */

document.addEventListener('DOMContentLoaded', () => {
  // 1. Feature Tabs Switcher
  const tabBtns = document.querySelectorAll('.tab-btn');
  const tabPanes = document.querySelectorAll('.tab-pane');

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-target');

      // Update active button
      tabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      // Update active pane
      tabPanes.forEach(pane => {
        if (pane.id === targetId) {
          pane.classList.add('active');
        } else {
          pane.classList.remove('active');
        }
      });
    });
  });

  // 2. Lightbox Modal for Screenshots
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = document.getElementById('lightbox-img');
  const lightboxClose = document.getElementById('lightbox-close');
  const lightboxBackdrop = document.getElementById('lightbox-backdrop');
  const zoomableImages = document.querySelectorAll('.img-zoomable');

  const openLightbox = (src, alt) => {
    lightboxImg.src = src;
    lightboxImg.alt = alt || '截图预览';
    lightbox.classList.add('active');
    lightbox.setAttribute('aria-hidden', 'false');
    document.body.style.overflow = 'hidden';
  };

  const closeLightbox = () => {
    lightbox.classList.remove('active');
    lightbox.setAttribute('aria-hidden', 'true');
    document.body.style.overflow = '';
  };

  zoomableImages.forEach(img => {
    img.addEventListener('click', () => {
      openLightbox(img.src, img.alt);
    });
  });

  if (lightboxClose) lightboxClose.addEventListener('click', closeLightbox);
  if (lightboxBackdrop) lightboxBackdrop.addEventListener('click', closeLightbox);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && lightbox.classList.contains('active')) {
      closeLightbox();
    }
  });

  // 3. One-Click Copy Command (for all .btn-copy buttons)
  const copyBtns = document.querySelectorAll('.btn-copy');
  copyBtns.forEach(btn => {
    btn.addEventListener('click', async () => {
      const textToCopy = btn.getAttribute('data-clipboard');
      const textSpan = btn.querySelector('span');
      const originalText = textSpan ? textSpan.textContent : '';

      try {
        await navigator.clipboard.writeText(textToCopy);
        if (textSpan) textSpan.textContent = '已复制！';
        btn.style.color = '#34c759';

        setTimeout(() => {
          if (textSpan) textSpan.textContent = originalText;
          btn.style.color = '';
        }, 2000);
      } catch (err) {
        console.error('Failed to copy text: ', err);
      }
    });
  });

  // 4. Mobile Navigation Toggle
  const navToggle = document.getElementById('nav-toggle');
  const navMenu = document.getElementById('nav-menu');

  if (navToggle && navMenu) {
    navToggle.addEventListener('click', () => {
      navMenu.classList.toggle('open');
    });

    // Close menu when clicking nav links on mobile
    navMenu.querySelectorAll('.nav-link').forEach(link => {
      link.addEventListener('click', () => {
        navMenu.classList.remove('open');
      });
    });
  }

  // 5. Scroll Header Shadow Polish
  const globalNav = document.getElementById('global-nav');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 20) {
      globalNav.style.borderBottomColor = 'rgba(255, 255, 255, 0.16)';
      globalNav.style.boxShadow = '0 4px 20px rgba(0, 0, 0, 0.4)';
    } else {
      globalNav.style.borderBottomColor = 'rgba(255, 255, 255, 0.08)';
      globalNav.style.boxShadow = 'none';
    }
  });
});
