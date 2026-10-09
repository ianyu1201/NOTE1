// Pointer and keyboard navigation share a bounded, non-wrapping card order.
export function cardGesture(dx: number, dy: number, vx = 0, vy = 0): "previous" | "next" | "tuck" | "cancel" {
  if (Math.abs(dy) >= 14 && Math.abs(dy) > Math.abs(dx) * 1.18 && (Math.abs(dy) > 64 || Math.abs(dy + vy * .18) > 96)) {
    return dy < 0 ? "next" : "previous";
  }
  if (dx <= -14 && Math.abs(dx) > Math.abs(dy) * 1.35 && (dx < -110 || dx + vx * .18 < -190)) return "tuck";
  return "cancel";
}

// A trackpad burst is one deliberate page turn; its momentum tail cannot skip cards.
export function cardWheel(state: { total: number; last: number; consumed: boolean }, dy: number, mode: number, now: number) {
  if (now - state.last > 180) { state.total = 0; state.consumed = false; }
  state.last = now;
  if (state.consumed) return 0;
  const pixels = dy * (mode === 1 ? 16 : mode === 2 ? 400 : 1);
  if (Math.sign(pixels) !== Math.sign(state.total)) state.total = 0;
  state.total += pixels;
  if (Math.abs(state.total) < 48) return 0;
  state.consumed = true;
  return Math.sign(state.total);
}

/** Small interruptible spring, using px/s velocity, with no animation dependency. */
export function settleCard(element: HTMLElement, vx = 0, vy = 0): () => void {
  const matrix = new DOMMatrixReadOnly(getComputedStyle(element).transform);
  let x = matrix.m41, y = matrix.m42, last = performance.now(), frame = 0;
  element.style.transition = "none";
  const write = () => { element.style.setProperty("--swipe-dx", `${x}px`); element.style.setProperty("--swipe-dy", `${y}px`); };
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { x = y = 0; write(); return () => {}; }
  const tick = (now: number) => {
    const dt = Math.min((now - last) / 1000, .024); last = now;
    vx += (-300 * x - 32 * vx) * dt; vy += (-300 * y - 32 * vy) * dt;
    x += vx * dt; y += vy * dt;
    if (Math.abs(x) + Math.abs(y) + Math.abs(vx) + Math.abs(vy) < .5) { x = y = 0; write(); return; }
    write(); frame = requestAnimationFrame(tick);
  };
  frame = requestAnimationFrame(tick);
  return () => cancelAnimationFrame(frame);
}

export function adjacentCardIndex(index: number, delta: number, count: number): number {
  return Math.max(0, Math.min(index + delta, count - 1));
}
