/* ===== Vercel Web Analytics & Speed Insights init queues ===== */
window.va = window.va || function () { (window.vaq = window.vaq || []).push(arguments); };
window.si = window.si || function () { (window.siq = window.siq || []).push(arguments); };

/* ===== Latest release fetch (version + asset info from GitHub) ===== */
(async function fetchLatestRelease() {
  try {
    const res = await fetch('https://api.github.com/repos/kaspars1985/runAI/releases/latest');
    if (!res.ok) return;
    const data = await res.json();

    const tagName = data.tag_name || 'v3.1.0';

    // Find dmg asset (prefer runAI.dmg, fall back to first .dmg)
    let dmgAsset = null;
    if (Array.isArray(data.assets)) {
      dmgAsset = data.assets.find(
        (a) => a && typeof a.name === 'string' && a.name.toLowerCase() === 'runai.dmg'
      ) || data.assets.find(
        (a) => a && typeof a.name === 'string' && a.name.toLowerCase().endsWith('.dmg')
      ) || null;
    }

    let sizeText = '~5.7 MB';
    if (dmgAsset && dmgAsset.size) {
      const mb = (dmgAsset.size / (1024 * 1024)).toFixed(1);
      sizeText = `${mb} MB`;
    }

    // Update DOM elements
    const navVer = document.getElementById('nav-version');
    const heroVer = document.getElementById('hero-version');
    const ctaVer = document.getElementById('cta-version');
    const heroSize = document.getElementById('hero-size');
    const dlText = document.getElementById('download-text');

    if (navVer) navVer.textContent = tagName;
    if (heroVer) heroVer.textContent = tagName;
    if (ctaVer) ctaVer.textContent = tagName;
    if (heroSize) heroSize.textContent = sizeText;
    if (dlText) dlText.textContent = `Lejupielādēt macOS (${tagName})`;

    if (
      dmgAsset &&
      typeof dmgAsset.browser_download_url === 'string' &&
      dmgAsset.browser_download_url.startsWith('https://github.com/')
    ) {
      const dlBtn = document.getElementById('download-btn');
      const ctaBtn = document.getElementById('cta-download-btn');
      if (dlBtn) dlBtn.href = dmgAsset.browser_download_url;
      if (ctaBtn) ctaBtn.href = dmgAsset.browser_download_url;
    }
  } catch (err) {
    console.warn('Could not fetch latest release:', err);
  }
})();

/* ===== Copy-to-clipboard buttons (data-copy) ===== */
(function initCopyButtons() {
  const buttons = document.querySelectorAll('[data-copy]');
  buttons.forEach((btn) => {
    btn.addEventListener('click', async () => {
      const cmd = btn.getAttribute('data-copy');
      if (!cmd) return;
      try {
        if (!navigator.clipboard || !navigator.clipboard.writeText) {
          throw new Error('no clipboard');
        }
        await navigator.clipboard.writeText(cmd);
        btn.textContent = 'Nokopēts!';
        if (btn._copyResetTimer) clearTimeout(btn._copyResetTimer);
        btn._copyResetTimer = setTimeout(() => {
          btn.textContent = 'Kopēt';
          btn._copyResetTimer = null;
        }, 2000);
      } catch (err) {
        // Fallback: select the sibling .select-all text so user can Cmd+C
        const parent = btn.parentElement;
        const selectAll = parent ? parent.querySelector('.select-all') : null;
        if (selectAll && window.getSelection && document.createRange) {
          const range = document.createRange();
          range.selectNodeContents(selectAll);
          const selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
        }
      }
    });
  });
})();

/* ===== Voice -> Text Morph Showcase Engine ===== */
(function initVoiceMorphStage() {
  const PHRASE_SETS = {
    lv: [
      "Šodien ir lieliska diena,",
      "lai uzsāktu kādu projektu"
    ],
    ltg: [
      "Loba dīna, kačs pi pīna,",
      "runoj latgaliski!"
    ]
  };
  let currentDialect = "lv";
  let PHRASES = PHRASE_SETS[currentDialect];

  const PHASE = {
    RECORD: 3200,
    MORPH: 1550,
    HOLD: 3200,
    DISSOLVE: 750
  };
  const TOTAL = PHASE.RECORD + PHASE.MORPH + PHASE.HOLD + PHASE.DISSOLVE;

  // 8 rhythmic syllable bursts matching:
  // "Šo-dien | ir | lie-lis-ka | die-na, | lai | uz-sāk-tu | kā-du | pro-jek-tu"
  const BURSTS = [
    [0.03, 0.14, 0.96],
    [0.16, 0.23, 0.65],
    [0.26, 0.40, 0.94],
    [0.43, 0.54, 0.82],
    [0.57, 0.64, 0.64],
    [0.67, 0.79, 0.92],
    [0.81, 0.88, 0.76],
    [0.89, 0.98, 0.90]
  ];

  const stage = document.getElementById("vmStage");
  const main = document.getElementById("vmMain");
  const canvas = document.getElementById("vmCanvas");
  const textLayer = document.getElementById("vmTextLayer");
  const pill = document.getElementById("vmPill");
  const pillText = document.getElementById("vmPillText");
  const timerEl = document.getElementById("vmTimer");
  const replayBtn = document.getElementById("vmReplay");
  const step1 = document.getElementById("step-card-1");
  const step2 = document.getElementById("step-card-2");
  const step3 = document.getElementById("step-card-3");

  if (!stage || !main || !canvas || !textLayer) return;
  const ctx = canvas.getContext("2d", { alpha: true });

  const prefersReducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const charEls = [];
  let caretEl = null;

  function buildTextLayer() {
    textLayer.innerHTML = "";
    charEls.length = 0;

    PHRASES.forEach((phrase, pIdx) => {
      const phraseSpan = document.createElement("span");
      phraseSpan.className = "vm-phrase";

      const words = phrase.split(" ");
      words.forEach((word, wIdx) => {
        const wordSpan = document.createElement("span");
        wordSpan.className = "vm-word";
        for (let i = 0; i < word.length; i++) {
          const span = document.createElement("span");
          span.className = "vm-char";
          span.textContent = word[i];
          wordSpan.appendChild(span);
          charEls.push(span);
        }
        phraseSpan.appendChild(wordSpan);

        if (wIdx < words.length - 1) {
          const spaceSpan = document.createElement("span");
          spaceSpan.className = "vm-char";
          spaceSpan.setAttribute("data-space", "true");
          spaceSpan.textContent = "\u00A0";
          phraseSpan.appendChild(spaceSpan);
          charEls.push(spaceSpan);
        }
      });

      textLayer.appendChild(phraseSpan);

      if (pIdx < PHRASES.length - 1) {
        const spaceSpan = document.createElement("span");
        spaceSpan.className = "vm-char vm-phrase-space";
        spaceSpan.setAttribute("data-space", "true");
        spaceSpan.textContent = "\u00A0";
        textLayer.appendChild(spaceSpan);
        charEls.push(spaceSpan);
      }
    });

    caretEl = document.createElement("span");
    caretEl.className = "vm-caret";
    caretEl.setAttribute("data-visible", "false");
    caretEl.setAttribute("data-blink", "false");
    textLayer.appendChild(caretEl);
  }

  let dpr = 1;
  let cssW = 0;
  let cssH = 0;
  let charMetrics = []; // { rightRel, topRel, height } relative to textLayer

  // Cached gradients (rebuilt on resize)
  let ribbonGradients = null; // [cyan, indigo, pink] horizontal 0..cssW
  let barGradients = null;    // [cyan, indigo, pink] vertical cy-maxBarH/2 .. cy+maxBarH/2

  function measureChars() {
    const savedTransforms = charEls.map((el) => el.style.transform);
    charEls.forEach((el) => { el.style.transform = "none"; });

    const layerRect = textLayer.getBoundingClientRect();
    charMetrics = charEls.map((el) => {
      const r = el.getBoundingClientRect();
      return {
        rightRel: r.right - layerRect.left,
        topRel: r.top - layerRect.top,
        height: r.height || 24
      };
    });

    charEls.forEach((el, i) => { el.style.transform = savedTransforms[i]; });
  }

  function buildGradients() {
    const w = cssW;
    const h = cssH;
    const cy = h / 2;
    const maxBarH = h * 0.54;

    // Horizontal ribbon gradients (0..cssW)
    const ribbonConfigs = [
      { c1: "rgba(34, 211, 238, 0.85)", c2: "rgba(34, 211, 238, 0)" },
      { c1: "rgba(99, 102, 241, 0.80)", c2: "rgba(99, 102, 241, 0)" },
      { c1: "rgba(236, 72, 153, 0.80)", c2: "rgba(236, 72, 153, 0)" }
    ];
    ribbonGradients = ribbonConfigs.map((cfg) => {
      const grad = ctx.createLinearGradient(0, 0, w, 0);
      grad.addColorStop(0, cfg.c2);
      grad.addColorStop(0.12, cfg.c1);
      grad.addColorStop(0.88, cfg.c1);
      grad.addColorStop(1, cfg.c2);
      return grad;
    });

    // Vertical bar gradients (cy - maxBarH/2 .. cy + maxBarH/2)
    const barConfigs = [
      {
        top: "rgba(103, 232, 249, 0.92)",
        mid: "rgba(34, 211, 238, 0.85)",
        bot: "rgba(59, 130, 246, 0.45)"
      },
      {
        top: "rgba(147, 197, 253, 0.92)",
        mid: "rgba(99, 102, 241, 0.85)",
        bot: "rgba(168, 85, 247, 0.45)"
      },
      {
        top: "rgba(240, 171, 252, 0.92)",
        mid: "rgba(236, 72, 153, 0.85)",
        bot: "rgba(244, 114, 182, 0.45)"
      }
    ];
    const yTop = cy - maxBarH / 2;
    const yBot = cy + maxBarH / 2;
    barGradients = barConfigs.map((cfg) => {
      const grad = ctx.createLinearGradient(0, yTop, 0, yBot);
      grad.addColorStop(0, cfg.top);
      grad.addColorStop(0.5, cfg.mid);
      grad.addColorStop(1, cfg.bot);
      return grad;
    });
  }

  function resize(force) {
    const rect = main.getBoundingClientRect();
    const newW = Math.max(1, rect.width);
    const newH = Math.max(1, rect.height);
    if (!force && newW === cssW && newH === cssH) return;

    dpr = Math.min(window.devicePixelRatio || 1, 2);
    cssW = newW;
    cssH = newH;
    canvas.width = Math.round(cssW * dpr);
    canvas.height = Math.round(cssH * dpr);
    canvas.style.width = cssW + "px";
    canvas.style.height = cssH + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    buildGradients();
    measureChars();
  }

  function voiceEnvelope(p) {
    if (p <= 0 || p >= 1) return 0.05;
    let amp = 0;
    for (let i = 0; i < BURSTS.length; i++) {
      const [s, e, peak] = BURSTS[i];
      if (p >= s && p <= e) {
        const local = (p - s) / (e - s);
        const bell = Math.sin(local * Math.PI);
        const micro = 0.72 + 0.28 * Math.sin(local * Math.PI * 5 + i * 1.9);
        amp = Math.max(amp, peak * bell * micro);
      }
    }
    return amp + 0.06 + 0.03 * Math.sin(p * 85);
  }

  const particles = [];
  const MAX_PARTICLES = 100;

  function spawnParticle(x, y, intensity, burstMode) {
    if (particles.length >= MAX_PARTICLES) return;
    const angle = burstMode
      ? (Math.random() - 0.5) * Math.PI * 1.4
      : Math.random() * Math.PI * 2;
    const speed = (burstMode ? 0.8 : 0.3) + Math.random() * 1.7 * intensity;
    const r = Math.random();
    particles.push({
      x,
      y,
      vx: Math.cos(angle) * speed * (burstMode ? 1.1 : 0.65),
      vy: Math.sin(angle) * speed - (burstMode ? 0.2 : 0.35),
      life: 1,
      decay: 0.014 + Math.random() * 0.022,
      size: 1.0 + Math.random() * 2.1,
      hue: r < 0.4 ? "cyan" : (r < 0.75 ? "purple" : "pink")
    });
  }

  function updateParticles() {
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vx *= 0.982;
      p.vy *= 0.982;
      p.life -= p.decay;
      if (p.life <= 0) particles.splice(i, 1);
    }
  }

  function drawParticles() {
    for (let i = 0; i < particles.length; i++) {
      const p = particles[i];
      const a = Math.max(0, p.life);
      let color;
      if (p.hue === "cyan") color = `rgba(34, 211, 238, ${a})`;
      else if (p.hue === "purple") color = `rgba(139, 92, 246, ${a})`;
      else color = `rgba(236, 72, 153, ${a})`;
      ctx.beginPath();
      ctx.fillStyle = color;
      ctx.arc(p.x, p.y, p.size * a, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function roundRect(c, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    c.beginPath();
    c.moveTo(x + r, y);
    c.lineTo(x + w - r, y);
    c.quadraticCurveTo(x + w, y, x + w, y + r);
    c.lineTo(x + w, y + h - r);
    c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    c.lineTo(x + r, y + h);
    c.quadraticCurveTo(x, y + h, x, y + h - r);
    c.lineTo(x, y + r);
    c.quadraticCurveTo(x, y, x + r, y);
    c.closePath();
  }

  const BAR_COUNT = 68;

  function drawScene(now, phase, phaseProgress, scanPos) {
    const w = cssW;
    const h = cssH;
    const cy = h / 2;

    ctx.clearRect(0, 0, w, h);

    let ampAtX;
    let compressAtX;
    let flareAtX;

    if (phase === "record") {
      const env = voiceEnvelope(phaseProgress);
      ampAtX = (nx) => {
        const centerBell = Math.sin(nx * Math.PI);
        const traveling = 0.65 + 0.35 * Math.sin(nx * 18 - now * 0.009);
        return env * (0.3 + 0.7 * centerBell) * traveling;
      };
      compressAtX = () => 0;
      flareAtX = () => 0;
    } else if (phase === "morph") {
      // As transcription starts, smoothly compress the wave toward center and fade it out
      const waveCollapse = Math.max(0, 1 - phaseProgress / 0.35);
      ampAtX = (nx) => {
        const centerBell = Math.sin(nx * Math.PI);
        return 0.5 * centerBell * waveCollapse * (0.8 + 0.2 * Math.sin(now * 0.01 + nx * 20));
      };
      compressAtX = (nx) => Math.min(1, phaseProgress * 3.0);
      flareAtX = (nx) => {
        if (phaseProgress > 0.35) return 0;
        return (1 - phaseProgress / 0.35) * 0.5;
      };
    } else if (phase === "hold") {
      ampAtX = () => 0;
      compressAtX = () => 1;
      flareAtX = () => 0;
    } else {
      // dissolve back to gentle idle wave only after text has faded out
      const emerge = Math.max(0, (phaseProgress - 0.45) / 0.55);
      ampAtX = (nx) => 0.18 * emerge * Math.sin(nx * Math.PI);
      compressAtX = () => 1 - emerge;
      flareAtX = () => 0;
    }

    // 1. Harmonic glowing ribbons (only visible when not in hold and during morph's early collapse)
    if (phase !== "hold") {
      let ribbonAlpha = 1;
      if (phase === "morph") {
        ribbonAlpha = Math.max(0, 1 - phaseProgress / 0.35);
      } else if (phase === "dissolve") {
        ribbonAlpha = Math.max(0, (phaseProgress - 0.45) / 0.55);
      }

      if (ribbonAlpha > 0.01 && ribbonGradients) {
        const ribbonConfigs = [
          { freq: 2.3, speed: 0.0042, offset: 0.0, width: 2.4 },
          { freq: 3.1, speed: -0.0036, offset: 2.1, width: 2.0 },
          { freq: 3.9, speed: 0.0048, offset: 4.2, width: 1.8 }
        ];

        ctx.save();
        ctx.globalAlpha = ribbonAlpha;
        ctx.globalCompositeOperation = "lighter";

        for (let r = 0; r < ribbonConfigs.length; r++) {
          const cfg = ribbonConfigs[r];
          ctx.beginPath();
          const steps = 130;
          for (let i = 0; i <= steps; i++) {
            const nx = i / steps;
            const x = nx * w;
            const amp = ampAtX(nx);
            const comp = compressAtX(nx);
            const flare = flareAtX(nx);

            const s1 = Math.sin(nx * Math.PI * cfg.freq + now * cfg.speed + cfg.offset);
            const s2 = Math.cos(nx * Math.PI * (cfg.freq * 1.8) - now * cfg.speed * 1.4 + cfg.offset);
            const wave = s1 * 0.68 + s2 * 0.32;

            const maxRibbonAmp = (34 + r * 8) * (0.2 + amp * 1.35);
            let y = cy + wave * maxRibbonAmp * (1 - comp);

            if (flare > 0) {
              y += Math.sin(nx * 45 + now * 0.025) * flare * 9 * (1 - comp * 0.5);
            }

            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
          }

          ctx.strokeStyle = ribbonGradients[r];
          ctx.lineWidth = cfg.width;
          ctx.stroke();
        }
        ctx.restore();
      }
    }

    // 2. Vertical spectral frequency bars
    let barAlpha = 1;
    if (phase === "morph") {
      barAlpha = Math.max(0, 1 - phaseProgress / 0.35);
    } else if (phase === "hold") {
      barAlpha = 0;
    } else if (phase === "dissolve") {
      barAlpha = Math.max(0, (phaseProgress - 0.45) / 0.55);
    }

    if (barAlpha > 0.01 && barGradients) {
      ctx.save();
      ctx.globalAlpha = barAlpha;
      ctx.globalCompositeOperation = "lighter";

      const barAreaW = w * 0.88;
      const barStartX = (w - barAreaW) / 2;
      const barGap = barAreaW / BAR_COUNT;
      const barW = Math.max(2.2, barGap * 0.52);
      const maxBarH = h * 0.54;

      for (let i = 0; i < BAR_COUNT; i++) {
        const nx = (i + 0.5) / BAR_COUNT;
        const x = barStartX + i * barGap + barGap / 2;
        const amp = ampAtX(nx);
        const comp = compressAtX(nx);
        const flare = flareAtX(nx);

        if (comp >= 0.98 && flare <= 0.02) continue;

        const seed = Math.sin(i * 12.9898) * 43758.5453;
        const rand = seed - Math.floor(seed);
        const harmonic = 0.55 + 0.45 * Math.sin(now * 0.0085 + i * 0.65 + rand * 5);

        let barH = maxBarH * amp * harmonic * (0.55 + rand * 0.65);
        barH = Math.max(3, barH);
        barH *= (1 - comp * 0.96);

        if (flare > 0) {
          barH += flare * 24 * (1 - comp * 0.4);
        }

        const y = cy - barH / 2;

        let gradIdx;
        if (nx < 0.35) gradIdx = 0;
        else if (nx < 0.68) gradIdx = 1;
        else gradIdx = 2;

        ctx.fillStyle = barGradients[gradIdx];

        roundRect(ctx, x - barW / 2, y, barW, barH, barW / 2);
        ctx.fill();

        if (phase === "record" && amp > 0.52 && Math.random() < 0.06) {
          spawnParticle(x, y, amp, false);
          spawnParticle(x, y + barH, amp, false);
        }
      }
      ctx.restore();
    }

    // 3. Morph Energy Burst Particles (clean, no boxy scanline overlay)
    if (phase === "morph" && phaseProgress < 0.35 && Math.random() < 0.45) {
      spawnParticle(w / 2 + (Math.random() - 0.5) * (w * 0.65), cy + (Math.random() - 0.5) * 24, 1.25, true);
    }

    // 4. Luminous Particles
    ctx.save();
    ctx.globalCompositeOperation = "lighter";
    drawParticles();
    ctx.restore();
  }

  function springOut(t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return 1 - Math.pow(1 - t, 3) * Math.cos(t * Math.PI * 1.35);
  }

  function setCharMorphState(el, idx, progress, dissolveAlpha) {
    if (progress <= 0.001) {
      el.style.opacity = "0";
      el.style.transform = "translate3d(0, 8px, 0) scaleY(2.35) scaleX(0.75)";
      return;
    }

    const clamped = Math.min(1, Math.max(0, progress));
    const sp = springOut(clamped);

    const scaleY = 2.35 - 1.35 * sp;
    const scaleX = 0.75 + 0.25 * sp;
    const dy = (1 - sp) * (idx % 2 === 0 ? -10 : 10);
    const alpha = Math.min(1, clamped * 1.45) * dissolveAlpha;

    el.style.opacity = alpha.toFixed(3);
    el.style.transform = `translate3d(0, ${dy.toFixed(1)}px, 0) scaleY(${scaleY.toFixed(3)}) scaleX(${scaleX.toFixed(3)})`;

    // Smooth chromatic morph without expensive dynamic CSS filter/textShadow re-rasterization
    if (clamped < 0.88) {
      const ratio = idx / Math.max(1, charEls.length - 1);
      if (ratio < 0.36) {
        el.style.color = "#a5f3fc";
      } else if (ratio < 0.7) {
        el.style.color = "#c4b5fd";
      } else {
        el.style.color = "#fbcfe8";
      }
    } else {
      el.style.color = "#ffffff";
    }
  }

  function positionCaretAfterChar(charIdx, visible, blink) {
    if (!caretEl || charMetrics.length === 0) return;
    caretEl.setAttribute("data-visible", visible ? "true" : "false");
    caretEl.setAttribute("data-blink", blink ? "true" : "false");
    if (!visible) return;

    const m = charMetrics[Math.max(0, Math.min(charMetrics.length - 1, charIdx))];
    if (!m) return;
    caretEl.style.height = `${Math.round(m.height * 0.88)}px`;
    caretEl.style.transform = `translate3d(${Math.round(m.rightRel + 2)}px, ${Math.round(m.topRel + m.height * 0.06)}px, 0)`;
  }

  let lastPhase = null;
  let lastTimerText = '';

  function updateCharsAndHUD(scanPos, phase, phaseProgress, elapsedMs) {
    const isMobile = window.innerWidth <= 640;
    const phaseChanged = lastPhase !== phase;

    if (phase === "record") {
      if (phaseChanged) {
        for (let i = 0; i < charEls.length; i++) {
          setCharMorphState(charEls[i], i, 0, 1);
        }
        positionCaretAfterChar(0, false, false);
        textLayer.setAttribute("data-glow", "false");

        pill.setAttribute("data-state", "recording");
        pillText.textContent = isMobile ? "⌥ Klausās..." : "⌥ Option turēts · Klausās balsi...";
        timerEl.style.opacity = "1";

        if (step1) step1.setAttribute("data-active", "blue");
        if (step2) step2.setAttribute("data-active", "purple");
        if (step3) step3.setAttribute("data-active", "none");
      }
      const sec = (elapsedMs / 1000).toFixed(1);
      const newText = `00:0${sec}`;
      if (newText !== lastTimerText) {
        timerEl.textContent = newText;
        lastTimerText = newText;
      }
      lastPhase = phase;
      return;
    }

    if (phase === "morph") {
      let lastIdx = 0;
      const totalChars = Math.max(1, charEls.length - 1);
      for (let i = 0; i < charEls.length; i++) {
        const seq = i / totalChars;
        const local = (scanPos - (seq - 0.04)) / 0.10;
        const t = Math.max(0, Math.min(1, local));
        setCharMorphState(charEls[i], i, t, 1);
        if (t > 0.15) lastIdx = i;
      }
      positionCaretAfterChar(lastIdx, scanPos > 0.03, false);

      if (phaseChanged) {
        textLayer.setAttribute("data-glow", "true");

        pill.setAttribute("data-state", "processing");
        pillText.textContent = isMobile ? "⚡ Atšifrē..." : "⚡ Atlaid taustiņu · Atšifrē (0.14s)...";

        if (step1) step1.setAttribute("data-active", "none");
        if (step2) step2.setAttribute("data-active", "purple");
        if (step3) step3.setAttribute("data-active", "emerald");
      }
      const newText = isMobile ? "GPU" : "Metal GPU";
      if (newText !== lastTimerText) {
        timerEl.textContent = newText;
        lastTimerText = newText;
      }
      lastPhase = phase;
      return;
    }

    if (phase === "hold") {
      if (phaseChanged) {
        for (let i = 0; i < charEls.length; i++) {
          setCharMorphState(charEls[i], i, 1, 1);
        }
        positionCaretAfterChar(charEls.length - 1, true, true);
        textLayer.setAttribute("data-glow", "true");

        pill.setAttribute("data-state", "done");
        pillText.textContent = "✓ Teksts gatavs";

        if (step1) step1.setAttribute("data-active", "none");
        if (step2) step2.setAttribute("data-active", "none");
        if (step3) step3.setAttribute("data-active", "emerald");
      }
      const newText = isMobile ? "Lokāli" : "100% lokāli";
      if (newText !== lastTimerText) {
        timerEl.textContent = newText;
        lastTimerText = newText;
      }
      lastPhase = phase;
      return;
    }

    // dissolve phase
    const fade = Math.max(0, 1 - phaseProgress * 1.25);
    for (let i = 0; i < charEls.length; i++) {
      setCharMorphState(charEls[i], i, 1, fade);
    }
    positionCaretAfterChar(charEls.length - 1, fade > 0.3, false);
    if (phaseChanged) {
      textLayer.setAttribute("data-glow", "false");
    }
    lastPhase = phase;
  }

  let cycleStart = performance.now();

  function restartCycle() {
    cycleStart = performance.now();
    particles.length = 0;
    lastPhase = null;
    lastTimerText = '';
    buildTextLayer();
    measureChars();
  }

  window.setDemoDialect = function(dialect) {
    if (!PHRASE_SETS[dialect]) return;
    currentDialect = dialect;
    PHRASES = PHRASE_SETS[dialect];
    restartCycle();
    if (prefersReducedMotion) {
      renderSettledFrame();
    }
  };

  stage.addEventListener("click", () => {
    restartCycle();
    if (prefersReducedMotion) {
      renderSettledFrame();
    }
  });
  if (replayBtn) {
    replayBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      restartCycle();
      if (prefersReducedMotion) {
        renderSettledFrame();
      }
    });
  }

  // Debounced resize via requestAnimationFrame
  let resizeRafId = null;
  window.addEventListener("resize", () => {
    if (resizeRafId !== null) return;
    resizeRafId = requestAnimationFrame(() => {
      resizeRafId = null;
      resize(false);
      if (prefersReducedMotion) {
        renderSettledFrame();
      }
    });
  });

  buildTextLayer();
  resize(true);
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(() => {
      resize(true);
      if (prefersReducedMotion) {
        renderSettledFrame();
      }
    });
  }

  // Renders the settled "hold" state once (used for reduced-motion)
  function renderSettledFrame() {
    ctx.clearRect(0, 0, cssW, cssH);
    updateCharsAndHUD(1, "hold", 1, 0);
  }

  let isVisible = true;
  let rafId = null;

  function scheduleTick() {
    if (!isVisible || rafId !== null) return;
    rafId = requestAnimationFrame(tick);
  }

  function tick(now) {
    rafId = null;
    if (!isVisible) return;

    const elapsed = (now - cycleStart) % TOTAL;
    let phase = "record";
    let phaseProgress = 0;
    let scanPos = 0;

    if (elapsed < PHASE.RECORD) {
      phase = "record";
      phaseProgress = elapsed / PHASE.RECORD;
    } else if (elapsed < PHASE.RECORD + PHASE.MORPH) {
      phase = "morph";
      phaseProgress = (elapsed - PHASE.RECORD) / PHASE.MORPH;
      // Smooth cubic ease-in-out for the morph sweep
      scanPos = phaseProgress < 0.5
        ? 2 * phaseProgress * phaseProgress
        : 1 - Math.pow(-2 * phaseProgress + 2, 2) / 2;
    } else if (elapsed < PHASE.RECORD + PHASE.MORPH + PHASE.HOLD) {
      phase = "hold";
      phaseProgress = (elapsed - PHASE.RECORD - PHASE.MORPH) / PHASE.HOLD;
      scanPos = 1;
    } else {
      phase = "dissolve";
      phaseProgress = (elapsed - PHASE.RECORD - PHASE.MORPH - PHASE.HOLD) / PHASE.DISSOLVE;
      scanPos = 1;
    }

    updateParticles();
    drawScene(now, phase, phaseProgress, scanPos);
    updateCharsAndHUD(scanPos, phase, phaseProgress, elapsed);

    scheduleTick();
  }

  if (prefersReducedMotion) {
    // Do not start the RAF loop; render the settled 'hold' frame once.
    renderSettledFrame();
    return;
  }

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver((entries) => {
      const entry = entries[0];
      isVisible = !!(entry && entry.isIntersecting);
      if (isVisible) {
        scheduleTick();
      } else if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    }, { threshold: 0.05 });
    observer.observe(stage);
  } else {
    scheduleTick();
  }
})();

/* ===== React Bits style DecryptedText Scramble for LAT[viski] [galiski] ===== */
(function initDecryptedTextEffect() {
  const glyphs = "!@#$%^&*~?0123456789abcdefghijklmnopqrstuvwxyz";
  const wrapper = document.getElementById("wordplayWrapper");
  const pills = document.querySelectorAll(".wordplay-pill");
  const prefersReducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function updateShift() {
    if (!wrapper) return;
    const lv = wrapper.querySelector(".wordplay-slot-lv");
    const ltg = wrapper.querySelector(".wordplay-slot-ltg");
    const punct = wrapper.querySelector(".wordplay-punct");
    if (!lv || !ltg || !punct) return;

    // Use offsetLeft which is layout-derived and completely unaffected by active CSS transforms or transitions
    const stemShift = Math.round(ltg.offsetLeft - lv.offsetLeft);
    const gap = window.innerWidth < 640 ? 2 : 4;
    const punctShift = Math.round(punct.offsetLeft - (lv.offsetLeft + lv.offsetWidth) - gap);

    if (stemShift > 0) {
      wrapper.style.setProperty("--wordplay-shift-x", `${stemShift}px`);
    }
    if (punctShift > 0) {
      wrapper.style.setProperty("--wordplay-punct-shift-x", `${punctShift}px`);
    }
  }

  function syncAriaPressed() {
    if (!wrapper) return;
    const state = wrapper.getAttribute("data-state");
    pills.forEach((p) => {
      const isLtg = p.classList.contains("wordplay-ltg");
      const mode = isLtg ? "ltg" : "lv";
      p.setAttribute("aria-pressed", state === mode ? "true" : "false");
    });
  }

  window.addEventListener("resize", updateShift);
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(updateShift);
  }
  setTimeout(updateShift, 50);
  setTimeout(updateShift, 200);
  setTimeout(updateShift, 600);

  let leaveTimer = null;

  // Map of pill -> its own scramble() function (used by idle interval)
  const scrambleFns = new Map();

  pills.forEach(pill => {
    const targetWord = pill.getAttribute("data-word");
    const span = pill.querySelector(".scramble-target");
    const isLtg = pill.classList.contains("wordplay-ltg");
    const mode = isLtg ? "ltg" : "lv";
    if (!span || !targetWord) return;

    let interval = null;

    function scramble() {
      if (interval) clearInterval(interval);
      let iteration = 0;
      const maxIterations = targetWord.length * 3;

      interval = setInterval(() => {
        span.textContent = targetWord
          .split("")
          .map((char, index) => {
            if (index < iteration / 3) {
              return targetWord[index];
            }
            return glyphs[Math.floor(Math.random() * glyphs.length)];
          })
          .join("");

        if (iteration >= maxIterations) {
          clearInterval(interval);
          interval = null;
          span.textContent = targetWord;
        }
        iteration++;
      }, 25);
    }

    scrambleFns.set(pill, scramble);

    pill.addEventListener("mouseenter", () => {
      if (leaveTimer) clearTimeout(leaveTimer);
      if (wrapper) wrapper.setAttribute("data-state", mode);
      syncAriaPressed();
      scramble();
    });

    pill.addEventListener("mouseleave", () => {
      if (leaveTimer) clearTimeout(leaveTimer);
      leaveTimer = setTimeout(() => {
        if (wrapper) {
          const isHovering = Array.from(pills).some(p => p.matches(":hover"));
          if (!isHovering) {
            wrapper.setAttribute("data-state", "none");
            syncAriaPressed();
          }
        }
      }, 60);
    });

    pill.addEventListener("click", (e) => {
      e.stopPropagation();
      if (leaveTimer) clearTimeout(leaveTimer);
      scramble();
      if (wrapper) {
        const current = wrapper.getAttribute("data-state");
        const next = current === mode ? "none" : mode;
        wrapper.setAttribute("data-state", next);
        syncAriaPressed();
      }
      if (window.setDemoDialect) {
        window.setDemoDialect(mode);
      }
    });
  });

  // Outside click reset
  document.addEventListener("click", (e) => {
    if (wrapper && !wrapper.contains(e.target)) {
      wrapper.setAttribute("data-state", "none");
      syncAriaPressed();
    }
  });

  // Initial aria-pressed sync
  syncAriaPressed();

  // Periodiska viegla alternējoša atšifrēšanas animācija dīkstāvē
  let toggle = false;
  setInterval(() => {
    if (document.hidden) return;
    if (prefersReducedMotion) return;
    if (wrapper && (wrapper.matches(":hover") || wrapper.getAttribute("data-state") !== "none")) return;
    const p = document.querySelector(toggle ? ".wordplay-ltg" : ".wordplay-lv");
    toggle = !toggle;
    if (!p) return;
    const fn = scrambleFns.get(p);
    if (fn) fn();
  }, 7000);
})();
