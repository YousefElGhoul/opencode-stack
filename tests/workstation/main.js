import './style.css'

document.querySelector('#status').textContent = 'Node, Vite and Tailwind loaded successfully.'
document.querySelector('#check').addEventListener('click', () => {
  document.querySelector('#status').textContent = 'Browser interaction succeeded.'
})
