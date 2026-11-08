/* KASSEN site: parallax, embers, reveals, trailer, lightbox, nav state. No dependencies. */
(function () {
  'use strict';
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* ---- Nav: solid background after the hero, current-section highlight ---- */
  var nav = $('#top-nav');
  var hero = $('.hero');
  var heroMedia = $('.hero__media');
  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      var y = window.scrollY || window.pageYOffset;
      nav.classList.toggle('is-solid', y > 40);
      if (!reduce && heroMedia && y < window.innerHeight * 1.2) {
        heroMedia.style.transform = 'translate3d(0,' + (y * 0.32).toFixed(1) + 'px,0)';
      }
      ticking = false;
    });
  }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  var links = $$('.nav__links a');
  if ('IntersectionObserver' in window && links.length) {
    var byId = {};
    links.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && byId[e.target.id]) {
          links.forEach(function (a) { a.removeAttribute('aria-current'); });
          byId[e.target.id].setAttribute('aria-current', 'true');
        }
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    Object.keys(byId).forEach(function (id) { var el = document.getElementById(id); if (el) spy.observe(el); });
  }

  /* ---- Embers drifting up through the hero ---- */
  var embers = $('.embers');
  if (embers && !reduce) {
    var n = window.innerWidth < 640 ? 14 : 30;
    for (var i = 0; i < n; i++) {
      var e = document.createElement('span');
      e.className = 'ember';
      var s = 2 + Math.random() * 4;
      e.style.cssText = 'left:' + (Math.random() * 100).toFixed(1) + '%;' +
        '--s:' + s.toFixed(1) + 'px;' +
        '--d:' + (9 + Math.random() * 12).toFixed(1) + 's;' +
        '--delay:' + (-Math.random() * 20).toFixed(1) + 's;' +
        '--dx:' + (Math.random() * 160 - 40).toFixed(0) + 'px;' +
        '--o:' + (0.35 + Math.random() * 0.55).toFixed(2);
      embers.appendChild(e);
    }
  }

  /* ---- Reveal on scroll ---- */
  var reveals = $$('.reveal');
  if (!reduce && 'IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('is-in'); });
  }

  /* ---- Videos: custom play overlay for the trailer, one video at a time ---- */
  var trailer = $('#trailer-video');
  var overlay = $('.screen__play');
  function playTrailer() {
    if (!trailer) return;
    if (overlay) overlay.hidden = true;
    var p = trailer.play();
    if (p && p.catch) p.catch(function () { /* autoplay with sound refused: controls remain */ });
  }
  if (overlay) overlay.addEventListener('click', function () { playTrailer(); trailer.focus(); });
  if (trailer) trailer.addEventListener('play', function () { if (overlay) overlay.hidden = true; });
  $$('[data-play-trailer]').forEach(function (a) {
    a.addEventListener('click', function (ev) {
      ev.preventDefault();
      var target = $('#trailer');
      target.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
      setTimeout(playTrailer, reduce ? 0 : 650);
    });
  });
  $$('video').forEach(function (v) {
    v.addEventListener('play', function () {
      $$('video').forEach(function (o) { if (o !== v && !o.paused) o.pause(); });
    });
  });

  /* ---- Gallery lightbox ---- */
  var dlg = $('#lightbox');
  var items = $$('#gallery-grid a');
  var lbImg = $('#lb-img');
  var lbCap = $('#lb-cap');
  var idx = 0;
  var opener = null;
  function show(i) {
    idx = (i + items.length) % items.length;
    var a = items[idx];
    lbImg.src = a.getAttribute('href');
    lbImg.alt = a.querySelector('img').alt;
    lbCap.textContent = a.getAttribute('data-caption') || '';
    // warm the next image
    var nx = new Image(); nx.src = items[(idx + 1) % items.length].getAttribute('href');
  }
  if (dlg && typeof dlg.showModal === 'function') {
    items.forEach(function (a, i) {
      a.addEventListener('click', function (ev) {
        ev.preventDefault();
        opener = a;
        show(i);
        dlg.showModal();
      });
    });
    dlg.addEventListener('click', function (ev) {
      var b = ev.target.closest('[data-lb]');
      if (b) {
        var act = b.getAttribute('data-lb');
        if (act === 'close') dlg.close();
        else show(idx + (act === 'next' ? 1 : -1));
        return;
      }
      if (ev.target === dlg || ev.target.tagName === 'FIGURE') dlg.close();
    });
    dlg.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowRight') { show(idx + 1); ev.preventDefault(); }
      if (ev.key === 'ArrowLeft') { show(idx - 1); ev.preventDefault(); }
    });
    var tx = null;
    dlg.addEventListener('touchstart', function (ev) { tx = ev.touches[0].clientX; }, { passive: true });
    dlg.addEventListener('touchend', function (ev) {
      if (tx === null) return;
      var dx = ev.changedTouches[0].clientX - tx;
      if (Math.abs(dx) > 50) show(idx + (dx < 0 ? 1 : -1));
      tx = null;
    });
    dlg.addEventListener('close', function () {
      lbImg.src = 'data:,';
      if (opener) opener.focus();
    });
  }
})();
