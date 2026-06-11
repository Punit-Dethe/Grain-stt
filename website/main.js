// ─── CUSTOM CURSOR ──────────────────────────────────────────────────────────
const cursor = Object.assign(document.createElement('div'), { className: 'cursor' })
const ring   = Object.assign(document.createElement('div'), { className: 'cursor-ring' })
document.body.append(cursor, ring)

let mx = innerWidth / 2, my = innerHeight / 2, rx = mx, ry = my
addEventListener('mousemove', e => { mx = e.clientX; my = e.clientY })
;(function loop() {
  rx += (mx - rx) * 0.12; ry += (my - ry) * 0.12
  cursor.style.cssText = `left:${mx}px;top:${my}px`
  ring.style.cssText   = `left:${rx}px;top:${ry}px`
  requestAnimationFrame(loop)
})()
document.querySelectorAll('a, button, [data-cursor]').forEach(el => {
  el.addEventListener('mouseenter', () => { cursor.classList.add('big'); ring.classList.add('big') })
  el.addEventListener('mouseleave', () => { cursor.classList.remove('big'); ring.classList.remove('big') })
})

// ─── NAV SCROLL ─────────────────────────────────────────────────────────────
const nav = document.getElementById('nav')
addEventListener('scroll', () => nav.classList.toggle('scrolled', scrollY > 40), { passive: true })

// ─── HERO DOT MATRIX (light theme — ink dots warming to orange) ──────────────
const canvas = document.getElementById('grid')
const ctx    = canvas.getContext('2d')
let dots = [], t = 0

function size() {
  canvas.width  = canvas.offsetWidth
  canvas.height = canvas.offsetHeight
  build()
}
function build() {
  dots = []
  const GAP = 26
  const cols = Math.ceil(canvas.width / GAP) + 1
  const rows = Math.ceil(canvas.height / GAP) + 1
  const ox = (canvas.width  - (cols - 1) * GAP) / 2
  const oy = (canvas.height - (rows - 1) * GAP) / 2
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++)
      dots.push({ x: ox + c * GAP, y: oy + r * GAP })
}
function draw() {
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  t += 0.006
  for (const d of dots) {
    const dx = d.x - mx, dy = d.y - my
    const dist = Math.hypot(dx, dy)
    const prox = Math.max(0, 1 - dist / 190)
    const wave = (Math.sin(t * 1.3 + d.x * 0.015 + d.y * 0.018) * 0.5 + 0.5) *
                 (Math.cos(t * 0.9 + d.x * 0.02 - d.y * 0.013) * 0.5 + 0.5)
    const baseA = 0.06 + wave * 0.10
    const a = baseA + prox * 0.7
    const radius = 1.7 + prox * 2.4
    if (prox > 0.02) {
      // warm to orange near cursor
      ctx.fillStyle = `rgba(255,93,30,${Math.min(prox * 0.95 + baseA, 1)})`
    } else {
      ctx.fillStyle = `rgba(23,19,14,${baseA})`
    }
    ctx.beginPath()
    ctx.arc(d.x, d.y, radius, 0, Math.PI * 2)
    ctx.fill()
  }
  requestAnimationFrame(draw)
}
new ResizeObserver(size).observe(canvas)
size(); draw()

// ─── PILL WAVEFORM (voice level only — no words) ─────────────────────────────
const wave = document.getElementById('pillWave')
const BARS = 11
const bars = []
for (let i = 0; i < BARS; i++) {
  const b = document.createElement('div')
  b.className = 'bar'
  wave.appendChild(b)
  bars.push({ el: b, phase: Math.random() * Math.PI * 2, speed: 0.06 + Math.random() * 0.05 })
}
let wt = 0
;(function animateWave() {
  wt += 1
  bars.forEach((b, i) => {
    // smooth pseudo-random voice envelope, taller in the middle
    const center = 1 - Math.abs(i - (BARS - 1) / 2) / ((BARS - 1) / 2)
    const v = (Math.sin(wt * b.speed + b.phase) * 0.5 + 0.5)
    const h = 4 + v * (6 + center * 18)
    b.el.style.height = h + 'px'
    b.el.style.opacity = 0.5 + v * 0.5
  })
  requestAnimationFrame(animateWave)
})()

// ─── SCROLL REVEAL ──────────────────────────────────────────────────────────
const io = new IntersectionObserver(
  es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target) } }),
  { threshold: 0.14 }
)
document.querySelectorAll('.reveal').forEach(el => io.observe(el))

// ─── ROUTING — cycle live provider ──────────────────────────────────────────
const provs = document.querySelectorAll('[data-prov]')
let pi = 0
if (provs.length) {
  provs[0].classList.add('live')
  setInterval(() => {
    provs[pi].classList.remove('live')
    pi = (pi + 1) % provs.length
    provs[pi].classList.add('live')
  }, 1600)
}
