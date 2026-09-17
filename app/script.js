document.getElementById('year').textContent = new Date().getFullYear();

const quotes = [
  "Coffee ka har cup, ek chhota sa sukoon hai.",
  "Subah achi ho to poora din achi guzarta hai.",
  "Achi guftagu ke liye achi coffee zaroori hai.",
  "Thodi der thehro, chuski lo, saans lo.",
  "Yahan waqt thoda dheere chalta hai — aur yehi khoobsurat hai."
];

let idx = 0;
const quoteBox = document.getElementById('quoteBox');
const quoteBtn = document.getElementById('quoteBtn');

quoteBtn.addEventListener('click', () => {
  idx = (idx + 1) % quotes.length;
  quoteBox.style.opacity = 0;
  setTimeout(() => {
    quoteBox.textContent = `"${quotes[idx]}"`;
    quoteBox.style.opacity = 1;
  }, 150);
});

quoteBox.style.transition = 'opacity 0.15s ease';
