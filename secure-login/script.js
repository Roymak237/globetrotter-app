/* ===================================================================
   SecureTech Security Portal — demonstration login interface
   -------------------------------------------------------------------
   Three independent pieces, in order:

     1. Particle network background (canvas)
     2. Self-typing terminal panel
     3. Login form interaction

   No authentication happens anywhere in this file. The submit handler
   never reads the value of any input, and nothing is sent over the
   network. The success state is a timed animation and nothing more.
=================================================================== */

(function () {
  "use strict";

  /* ----------------------------------------------------------------
     Shared motion preference

     Read once, then watched. Someone who turns the setting on while
     the page is open should see the animation stop, not wait for a
     reload.
  ---------------------------------------------------------------- */

  var motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  var reduceMotion = motionQuery.matches;
  var motionListeners = [];

  function onMotionChange(callback) {
    motionListeners.push(callback);
  }

  function handleMotionChange(event) {
    reduceMotion = event.matches;
    for (var i = 0; i < motionListeners.length; i++) {
      motionListeners[i](reduceMotion);
    }
  }

  if (typeof motionQuery.addEventListener === "function") {
    motionQuery.addEventListener("change", handleMotionChange);
  } else if (typeof motionQuery.addListener === "function") {
    // Safari before 14 only has the deprecated form.
    motionQuery.addListener(handleMotionChange);
  }

  /* ================================================================
     1. PARTICLE NETWORK
  ================================================================ */

  var NETWORK = {
    /** One particle per this many CSS pixels of viewport area. */
    density: 1 / 17000,
    /** Hard limits, so a 4K monitor does not melt and a phone is not bare. */
    minParticles: 22,
    maxParticles: 78,
    /** Particles closer than this (CSS px) are joined by a line. */
    linkDistance: 148,
    /** Drift speed in CSS pixels per second. */
    speed: 11,
    /** Dot radius range in CSS pixels. */
    minRadius: 0.9,
    maxRadius: 2.2,
    /** Milliseconds between attempts to launch a pulse along a link. */
    pulseEvery: 820,
    maxPulses: 7,
    pulseSpeed: 0.85,
    /** Device pixel ratio is capped: beyond 2 the extra cost buys nothing. */
    maxPixelRatio: 2
  };

  var canvas = document.getElementById("network");
  var ctx = canvas ? canvas.getContext("2d") : null;

  var particles = [];
  var pulses = [];
  var viewWidth = 0;
  var viewHeight = 0;
  var frameHandle = 0;
  var lastFrame = 0;
  var pulseClock = 0;
  var resizeHandle = 0;

  function buildParticles() {
    var target = Math.round(viewWidth * viewHeight * NETWORK.density);
    var count = Math.max(NETWORK.minParticles, Math.min(NETWORK.maxParticles, target));

    particles = [];
    for (var i = 0; i < count; i++) {
      var angle = Math.random() * Math.PI * 2;
      // A little speed variation stops the field looking like a single
      // sheet sliding in one direction.
      var pace = NETWORK.speed * (0.35 + Math.random() * 0.9);

      particles.push({
        x: Math.random() * viewWidth,
        y: Math.random() * viewHeight,
        vx: Math.cos(angle) * pace,
        vy: Math.sin(angle) * pace,
        r: NETWORK.minRadius + Math.random() * (NETWORK.maxRadius - NETWORK.minRadius),
        // Used only to desynchronise the gentle brightness breathing.
        phase: Math.random() * Math.PI * 2
      });
    }

    // Pulses hold indices into `particles`, so they cannot outlive it.
    pulses = [];
  }

  function resizeCanvas() {
    if (!canvas || !ctx) return;

    var ratio = Math.min(window.devicePixelRatio || 1, NETWORK.maxPixelRatio);
    viewWidth = canvas.clientWidth;
    viewHeight = canvas.clientHeight;

    canvas.width = Math.round(viewWidth * ratio);
    canvas.height = Math.round(viewHeight * ratio);

    // Draw in CSS pixels and let the transform handle the density.
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);

    buildParticles();
  }

  function spawnPulse() {
    if (pulses.length >= NETWORK.maxPulses || particles.length < 2) return;

    var from = (Math.random() * particles.length) | 0;
    var a = particles[from];
    var limitSquared = NETWORK.linkDistance * NETWORK.linkDistance;

    // Walk the list from a random offset so the same neighbour is not
    // always picked first.
    var offset = (Math.random() * particles.length) | 0;
    for (var step = 0; step < particles.length; step++) {
      var to = (offset + step) % particles.length;
      if (to === from) continue;

      var b = particles[to];
      var dx = a.x - b.x;
      var dy = a.y - b.y;
      if (dx * dx + dy * dy < limitSquared) {
        pulses.push({ from: from, to: to, t: 0 });
        return;
      }
    }
  }

  function update(dt) {
    var i;

    for (i = 0; i < particles.length; i++) {
      var p = particles[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;

      // Wrap rather than bounce: wrapping has no edges for particles to
      // pile up against, so the field stays evenly spread forever.
      if (p.x < -20) p.x = viewWidth + 20;
      else if (p.x > viewWidth + 20) p.x = -20;
      if (p.y < -20) p.y = viewHeight + 20;
      else if (p.y > viewHeight + 20) p.y = -20;
    }

    for (i = pulses.length - 1; i >= 0; i--) {
      pulses[i].t += NETWORK.pulseSpeed * dt;
      if (pulses[i].t >= 1) pulses.splice(i, 1);
    }
  }

  function draw(time) {
    if (!ctx) return;

    ctx.clearRect(0, 0, viewWidth, viewHeight);

    var limit = NETWORK.linkDistance;
    var limitSquared = limit * limit;
    var i;
    var j;

    /* Links. One pass over every unordered pair. At the particle counts
       above this is a few thousand cheap comparisons per frame, which is
       far less work than maintaining a spatial index would cost. */
    ctx.lineWidth = 1;
    for (i = 0; i < particles.length; i++) {
      var a = particles[i];
      for (j = i + 1; j < particles.length; j++) {
        var b = particles[j];
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        var distSquared = dx * dx + dy * dy;
        if (distSquared > limitSquared) continue;

        var strength = 1 - Math.sqrt(distSquared) / limit;
        ctx.strokeStyle = "rgba(60, 170, 255, " + (strength * 0.34).toFixed(3) + ")";
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }
    }

    /* Pulses travelling along a link. */
    for (i = 0; i < pulses.length; i++) {
      var pulse = pulses[i];
      var start = particles[pulse.from];
      var end = particles[pulse.to];
      if (!start || !end) continue;

      var t = pulse.t;
      var px = start.x + (end.x - start.x) * t;
      var py = start.y + (end.y - start.y) * t;
      // Fade in and out, so a pulse never appears or vanishes abruptly.
      var fade = Math.sin(t * Math.PI);

      ctx.fillStyle = "rgba(190, 245, 255, " + (fade * 0.95).toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(px, py, 2.1, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = "rgba(60, 200, 255, " + (fade * 0.3).toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(px, py, 5.5, 0, Math.PI * 2);
      ctx.fill();
    }

    /* Particles. Two flat circles per particle imitate a glow for a
       fraction of the cost of a per-particle radial gradient. */
    for (i = 0; i < particles.length; i++) {
      var dot = particles[i];
      var breathe = 0.6 + 0.4 * Math.sin(time * 0.0014 + dot.phase);

      ctx.fillStyle = "rgba(60, 190, 255, " + (breathe * 0.1).toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(dot.x, dot.y, dot.r * 3.4, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = "rgba(170, 232, 255, " + (breathe * 0.85).toFixed(3) + ")";
      ctx.beginPath();
      ctx.arc(dot.x, dot.y, dot.r, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function tick(time) {
    frameHandle = window.requestAnimationFrame(tick);

    // Clamped, so returning to a backgrounded tab does not teleport every
    // particle across the screen in one frame.
    var dt = Math.min((time - lastFrame) / 1000, 0.05);
    lastFrame = time;

    pulseClock += dt * 1000;
    if (pulseClock >= NETWORK.pulseEvery) {
      pulseClock = 0;
      spawnPulse();
    }

    update(dt);
    draw(time);
  }

  function startNetwork() {
    if (!ctx || frameHandle) return;
    lastFrame = window.performance.now();
    frameHandle = window.requestAnimationFrame(tick);
  }

  function stopNetwork() {
    if (!frameHandle) return;
    window.cancelAnimationFrame(frameHandle);
    frameHandle = 0;
  }

  function applyNetworkMotionPreference() {
    if (reduceMotion) {
      stopNetwork();
      // One static frame: the design still reads, nothing moves.
      draw(0);
    } else {
      startNetwork();
    }
  }

  if (ctx) {
    resizeCanvas();
    applyNetworkMotionPreference();

    window.addEventListener("resize", function () {
      // Resizing fires in bursts; rebuild once the burst settles.
      if (resizeHandle) window.cancelAnimationFrame(resizeHandle);
      resizeHandle = window.requestAnimationFrame(function () {
        resizeHandle = 0;
        resizeCanvas();
        if (reduceMotion) draw(0);
      });
    });

    onMotionChange(applyNetworkMotionPreference);
  }

  /* ================================================================
     2. TERMINAL

     Non-sensitive sample code, typed one character at a time. Each line
     is a list of tokens so it can be coloured without parsing anything.
  ================================================================ */

  var CODE = [
    [{ text: "// SecureTech runtime integrity check", cls: "comment" }],
    [
      { text: "const ", cls: "kw" },
      { text: "securityStatus", cls: "var" },
      { text: " = ", cls: "op" },
      { text: "\"ACTIVE\"", cls: "str" },
      { text: ";", cls: "op" }
    ],
    [
      { text: "const ", cls: "kw" },
      { text: "encryption", cls: "var" },
      { text: " = ", cls: "op" },
      { text: "\"AES-256\"", cls: "str" },
      { text: ";", cls: "op" }
    ],
    [
      { text: "const ", cls: "kw" },
      { text: "authentication", cls: "var" },
      { text: " = ", cls: "op" },
      { text: "\"READY\"", cls: "str" },
      { text: ";", cls: "op" }
    ],
    [
      { text: "const ", cls: "kw" },
      { text: "activeNodes", cls: "var" },
      { text: " = ", cls: "op" },
      { text: "128", cls: "num" },
      { text: ";", cls: "op" }
    ],
    [],
    [
      { text: "monitor", cls: "fn" },
      { text: ".", cls: "op" },
      { text: "watch", cls: "fn" },
      { text: "(", cls: "op" },
      { text: "\"perimeter\"", cls: "str" },
      { text: ");", cls: "op" }
    ]
  ];

  var TYPE_SPEED = 34;       // milliseconds per character
  var LINE_PAUSE = 320;      // pause at the end of each line
  var LOOP_PAUSE = 2600;     // pause before the panel clears and restarts

  var terminalBody = document.getElementById("terminal-body");
  var typeTimer = 0;
  var lineIndex = 0;
  var charIndex = 0;

  /** Flattens a token line to plain text so its length is easy to count. */
  function lineLength(line) {
    var total = 0;
    for (var i = 0; i < line.length; i++) total += line[i].text.length;
    return total;
  }

  /**
   * Renders one line up to `limit` characters.
   *
   * Nodes are built with `textContent` rather than assembled as an HTML
   * string. The content here is a hardcoded constant, but building DOM
   * directly keeps it that way even if someone later feeds this real text.
   */
  function renderLine(target, line, limit) {
    while (target.firstChild) target.removeChild(target.firstChild);

    var used = 0;
    for (var i = 0; i < line.length; i++) {
      if (used >= limit) break;

      var token = line[i];
      var slice = token.text.slice(0, Math.max(0, limit - used));
      used += token.text.length;

      if (!slice) continue;

      var span = document.createElement("span");
      span.className = "tok-" + token.cls;
      span.textContent = slice;
      target.appendChild(span);
    }
  }

  function clearTerminal() {
    if (!terminalBody) return;
    while (terminalBody.firstChild) {
      terminalBody.removeChild(terminalBody.firstChild);
    }
  }

  /** Draws every line in full, with no animation. */
  function renderTerminalComplete() {
    if (!terminalBody) return;
    clearTerminal();

    for (var i = 0; i < CODE.length; i++) {
      var row = document.createElement("div");
      renderLine(row, CODE[i], Infinity);
      if (!CODE[i].length) row.appendChild(document.createTextNode("\u00a0"));
      terminalBody.appendChild(row);
    }
  }

  function typeStep() {
    if (!terminalBody) return;

    if (lineIndex >= CODE.length) {
      // Finished. Hold the completed block, then start over.
      typeTimer = window.setTimeout(function () {
        lineIndex = 0;
        charIndex = 0;
        clearTerminal();
        typeStep();
      }, LOOP_PAUSE);
      return;
    }

    var line = CODE[lineIndex];
    var row = terminalBody.childNodes[lineIndex];

    if (!row) {
      row = document.createElement("div");
      terminalBody.appendChild(row);
    }

    renderLine(row, line, charIndex);

    // The caret rides the end of whichever line is being typed.
    var caret = document.createElement("span");
    caret.className = "caret";
    row.appendChild(caret);

    if (charIndex >= lineLength(line)) {
      row.removeChild(caret);
      if (!line.length) row.appendChild(document.createTextNode("\u00a0"));
      lineIndex++;
      charIndex = 0;
      typeTimer = window.setTimeout(typeStep, LINE_PAUSE);
      return;
    }

    charIndex++;
    // A small random wobble reads as typing; a fixed interval reads as a
    // machine printing.
    typeTimer = window.setTimeout(typeStep, TYPE_SPEED + Math.random() * 45);
  }

  function startTyping() {
    if (!terminalBody || typeTimer || reduceMotion) return;
    typeStep();
  }

  function stopTyping() {
    if (!typeTimer) return;
    window.clearTimeout(typeTimer);
    typeTimer = 0;
  }

  function applyTerminalMotionPreference() {
    if (reduceMotion) {
      stopTyping();
      renderTerminalComplete();
    } else {
      lineIndex = 0;
      charIndex = 0;
      clearTerminal();
      startTyping();
    }
  }

  if (terminalBody) {
    applyTerminalMotionPreference();
    onMotionChange(applyTerminalMotionPreference);
  }

  /* ================================================================
     3. VISIBILITY

     A hidden tab gets no animation at all. requestAnimationFrame is
     already throttled by the browser, but the typing timer is not, and
     neither is worth running for a page nobody is looking at.
  ================================================================ */

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      stopNetwork();
      stopTyping();
    } else if (!reduceMotion) {
      startNetwork();
      startTyping();
    }
  });

  /* ================================================================
     4. LOGIN FORM

     Presentation only. Nothing below reads an input value.
  ================================================================ */

  var form = document.getElementById("login-form");
  var submit = document.getElementById("submit");
  var status = document.getElementById("status");
  var reveal = document.getElementById("reveal");
  var password = document.getElementById("password");

  var LOADING_MS = 1600;
  var LOADING_MS_REDUCED = 450;
  var RESET_MS = 3800;

  var busy = false;
  var formTimers = [];

  function later(fn, delay) {
    formTimers.push(window.setTimeout(fn, delay));
  }

  function clearFormTimers() {
    for (var i = 0; i < formTimers.length; i++) {
      window.clearTimeout(formTimers[i]);
    }
    formTimers = [];
  }

  function setStatus(message, isSuccess) {
    if (!status) return;
    status.textContent = message;
    status.classList.toggle("is-visible", Boolean(message));
    status.classList.toggle("is-success", Boolean(isSuccess));
  }

  /* Show / hide password. The button reports its own state through
     aria-pressed, which is also what swaps the icon in CSS. */
  if (reveal && password) {
    reveal.addEventListener("click", function () {
      var nowVisible = password.type === "password";
      password.type = nowVisible ? "text" : "password";
      reveal.setAttribute("aria-pressed", String(nowVisible));
      reveal.setAttribute("aria-label", nowVisible ? "Hide password" : "Show password");
      password.focus();
    });
  }

  if (form && submit) {
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (busy) return;

      busy = true;
      clearFormTimers();

      submit.disabled = true;
      submit.classList.remove("is-done");
      submit.classList.add("is-loading");
      setStatus("Verifying credentials\u2026", false);

      var wait = reduceMotion ? LOADING_MS_REDUCED : LOADING_MS;

      later(function () {
        submit.classList.remove("is-loading");
        submit.classList.add("is-done");
        setStatus("Authentication successful", true);

        // Return to the idle state so the demonstration can be run again.
        later(function () {
          submit.classList.remove("is-done");
          submit.disabled = false;
          setStatus("", false);
          busy = false;
        }, RESET_MS);
      }, wait);
    });
  }
})();
