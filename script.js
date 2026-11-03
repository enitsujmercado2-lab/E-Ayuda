const togglePassword = document.querySelector('.toggle-password');
const passwordInput = document.querySelector('#password');

togglePassword.addEventListener('click', () => {
  passwordInput.type = passwordInput.type === 'password' ? 'text' : 'password';
  togglePassword.classList.toggle('ri-eye-off-line');
  togglePassword.classList.toggle('ri-eye-line');
});


// remember me 
if (localStorage.savedName) {
  FullName.value = localStorage.savedName;
  password.value = localStorage.savedPassword;
  rememberMe.checked = true;
}

document.querySelector(".login-form").onsubmit = () => {
  if (rememberMe.checked) {
    localStorage.savedName = FullName.value;
    localStorage.savedPassword = password.value;
  } else {
    localStorage.removeItem("savedName");
    localStorage.removeItem("savedPassword");
  }
};