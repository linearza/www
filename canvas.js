(function () {
  var canvas = document.getElementById("circuit");
  var ctx = canvas.getContext("2d");

  var COLORS = ["rgba(0, 212, 255,", "rgba(255, 0, 128,", "rgba(0, 255, 136,"];
  var GLOW = "rgba(255, 182, 39,";

  var CONNECT_DIST = 140;
  var NODE_COUNT = 48;

  var nodes = [];
  var animId;

  function buildNodes(w, h) {
    return Array.from({ length: NODE_COUNT }, function () {
      return {
        x: Math.random() * w,
        y: Math.random() * h,
        vx: (Math.random() - 0.5) * 0.4,
        vy: (Math.random() - 0.5) * 0.4,
        color: COLORS[Math.floor(Math.random() * COLORS.length)],
        pulsePhase: Math.random() * Math.PI * 2,
      };
    });
  }

  function resize() {
    canvas.width = window.innerWidth * devicePixelRatio;
    canvas.height = window.innerHeight * devicePixelRatio;
    canvas.style.width = window.innerWidth + "px";
    canvas.style.height = window.innerHeight + "px";
    ctx.scale(devicePixelRatio, devicePixelRatio);
    nodes = buildNodes(window.innerWidth, window.innerHeight);
  }

  function draw(t) {
    var w = window.innerWidth;
    var h = window.innerHeight;

    ctx.clearRect(0, 0, w, h);

    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      node.x += node.vx;
      node.y += node.vy;
      if (node.x < 0 || node.x > w) node.vx *= -1;
      if (node.y < 0 || node.y > h) node.vy *= -1;
      node.pulsePhase += 0.02;
    }

    for (var a = 0; a < nodes.length; a++) {
      for (var b = a + 1; b < nodes.length; b++) {
        var na = nodes[a];
        var nb = nodes[b];
        var dx = na.x - nb.x;
        var dy = na.y - nb.y;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < CONNECT_DIST) {
          var alpha = (1 - dist / CONNECT_DIST) * 0.35;
          ctx.strokeStyle = na.color + " " + alpha + ")";
          ctx.lineWidth = (1 - dist / CONNECT_DIST) * 1.2;
          ctx.beginPath();
          ctx.moveTo(na.x, na.y);
          ctx.lineTo(na.x, nb.y);
          ctx.lineTo(nb.x, nb.y);
          ctx.stroke();
        }
      }
    }

    var glowX = w * 0.82;
    var glowY = h * 0.12;
    var glowPulse = 0.7 + 0.3 * Math.sin(t * 0.0008);
    var grad = ctx.createRadialGradient(glowX, glowY, 0, glowX, glowY, w * 0.35);
    grad.addColorStop(0, GLOW + (0.18 * glowPulse) + ")");
    grad.addColorStop(0.5, GLOW + (0.06 * glowPulse) + ")");
    grad.addColorStop(1, GLOW + "0)");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    for (var n = 0; n < nodes.length; n++) {
      var nd = nodes[n];
      var pulse = 0.5 + 0.5 * Math.sin(nd.pulsePhase + t * 0.001);
      ctx.beginPath();
      ctx.arc(nd.x, nd.y, 2 + pulse * 2, 0, Math.PI * 2);
      ctx.fillStyle = nd.color + " " + (0.4 + pulse * 0.5) + ")";
      ctx.fill();
    }

    animId = requestAnimationFrame(draw);
  }

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
      GLOW = glow;
      for (var i = 0; i < nodes.length; i++) {
        nodes[i].color = COLORS[Math.floor(Math.random() * COLORS.length)];
      }
    },
  };
})();
