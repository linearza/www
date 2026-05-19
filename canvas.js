(function () {
  var canvas = document.getElementById("circuit");
  var ctx    = canvas.getContext("2d");

  var COLORS = ["rgba(0,212,255,", "rgba(255,0,128,", "rgba(0,255,136,"];
  var GLOW   = "rgba(255,182,39,";

  var ripples = [];
  var COLS, ROWS, SPACING;
  var points  = [];

  var SPRING  = 0.012;
  var DAMPING = 0.96;

  function buildGrid(w, h) {
    SPACING = Math.max(44, Math.min(72, Math.round(Math.min(w, h) / 15)));
    COLS    = Math.ceil(w / SPACING) + 2;
    ROWS    = Math.ceil(h / SPACING) + 2;
    var ox  = -(COLS * SPACING - w) / 2;
    var oy  = -(ROWS * SPACING - h) / 2;
    var pts = [];
    for (var r = 0; r < ROWS; r++) {
      for (var c = 0; c < COLS; c++) {
        var rx = ox + c * SPACING;
        var ry = oy + r * SPACING;
        pts.push({ rx: rx, ry: ry, x: rx, y: ry, vx: 0, vy: 0 });
      }
    }
    return pts;
  }

  function resize() {
    var w = window.innerWidth;
    var h = window.innerHeight;
    canvas.width        = w * devicePixelRatio;
    canvas.height       = h * devicePixelRatio;
    canvas.style.width  = w + "px";
    canvas.style.height = h + "px";
    ctx.scale(devicePixelRatio, devicePixelRatio);
    points  = buildGrid(w, h);
    ripples = [];
  }

  function at(c, r) { return r * COLS + c; }

  var animId;
  function draw(t) {
    var w  = window.innerWidth;
    var h  = window.innerHeight;
    var ts = t * 0.00022; // master time scale — keep very slow
    ctx.clearRect(0, 0, w, h);

    // ── update each point toward its gently-waving target ────────────────────
    for (var i = 0; i < points.length; i++) {
      var p = points[i];

      // overlapping slow sine waves give a fluid, non-repeating feel
      var tx = p.rx
        + Math.sin(p.ry * 0.011 + ts * 1.1) * 7
        + Math.sin(p.rx * 0.008 + ts * 0.7) * 4;
      var ty = p.ry
        + Math.cos(p.rx * 0.011 + ts * 0.9) * 7
        + Math.cos(p.ry * 0.008 + ts * 1.3) * 4;

      var fx = -SPRING * (p.x - tx);
      var fy = -SPRING * (p.y - ty);

      // ripple rings
      for (var ri = 0; ri < ripples.length; ri++) {
        var rp  = ripples[ri];
        var rdx = p.x - rp.x;
        var rdy = p.y - rp.y;
        var rd  = Math.sqrt(rdx * rdx + rdy * rdy);
        if (rd > 0.5) {
          var wave = rd - rp.radius;
          if (Math.abs(wave) < 35) {
            var rf = rp.strength * Math.exp(-(wave * wave) / 500) / rd;
            fx += rdx * rf;
            fy += rdy * rf;
          }
        }
      }

      p.vx = (p.vx + fx) * DAMPING;
      p.vy = (p.vy + fy) * DAMPING;
      p.x += p.vx;
      p.y += p.vy;
    }

    // age ripples
    for (var ri = ripples.length - 1; ri >= 0; ri--) {
      ripples[ri].radius   += 4;
      ripples[ri].strength *= 0.978;
      if (ripples[ri].strength < 0.4) ripples.splice(ri, 1);
    }

    // ── draw grid ─────────────────────────────────────────────────────────────
    for (var r = 0; r < ROWS; r++) {
      for (var c = 0; c < COLS; c++) {
        var p   = points[at(c, r)];
        var ddx = p.x - p.rx;
        var ddy = p.y - p.ry;
        var disp = Math.sqrt(ddx * ddx + ddy * ddy);
        var t01  = Math.min(1, disp / 30);
        var alpha = 0.10 + t01 * 0.22;

        if (c < COLS - 1) {
          var pr = points[at(c + 1, r)];
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(pr.x, pr.y);
          ctx.lineWidth   = 0.5 + t01 * 0.6;
          ctx.strokeStyle = t01 > 0.3 ? COLORS[1] + alpha + ")" : COLORS[0] + alpha + ")";
          ctx.stroke();
        }
        if (r < ROWS - 1) {
          var pb = points[at(c, r + 1)];
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(pb.x, pb.y);
          ctx.lineWidth   = 0.5 + t01 * 0.6;
          ctx.strokeStyle = t01 > 0.3 ? COLORS[1] + alpha + ")" : COLORS[0] + alpha + ")";
          ctx.stroke();
        }
      }
    }

    // ── intersection dots ─────────────────────────────────────────────────────
    for (var i = 0; i < points.length; i++) {
      var p    = points[i];
      var ddx  = p.x - p.rx;
      var ddy  = p.y - p.ry;
      var disp = Math.sqrt(ddx * ddx + ddy * ddy);
      if (disp < 2) continue;
      var t01 = Math.min(1, disp / 25);
      ctx.beginPath();
      ctx.arc(p.x, p.y, 0.8 + t01 * 1.8, 0, Math.PI * 2);
      ctx.fillStyle = COLORS[2] + (0.15 + t01 * 0.6) + ")";
      ctx.fill();
    }

    // ── ambient glow ──────────────────────────────────────────────────────────
    var glowX = w * 0.82;
    var glowY = h * 0.12;
    var pulse = 0.7 + 0.3 * Math.sin(t * 0.0006);
    var grad  = ctx.createRadialGradient(glowX, glowY, 0, glowX, glowY, w * 0.35);
    grad.addColorStop(0,   GLOW + (0.18 * pulse) + ")");
    grad.addColorStop(0.5, GLOW + (0.06 * pulse) + ")");
    grad.addColorStop(1,   GLOW + "0)");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    animId = requestAnimationFrame(draw);
  }

  // click for desktop, touchstart for immediate mobile response
  window.addEventListener("click", function (e) {
    ripples.push({ x: e.clientX, y: e.clientY, radius: 0, strength: 5 });
  });

  window.addEventListener("touchstart", function (e) {
    for (var i = 0; i < e.changedTouches.length; i++) {
      var t = e.changedTouches[i];
      ripples.push({ x: t.clientX, y: t.clientY, radius: 0, strength: 5 });
    }
  }, { passive: true });

  resize();
  window.addEventListener("resize", function () {
    cancelAnimationFrame(animId);
    resize();
    animId = requestAnimationFrame(draw);
  });

  animId = requestAnimationFrame(draw);

  window.canvasTheme = {
    set: function (colors, glow) {
      COLORS = colors;
      GLOW   = glow;
    },
  };
})();
