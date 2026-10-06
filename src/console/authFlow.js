export const MIN_PASSWORD_LENGTH = 8;

export function consoleRedirect(origin) {
  return `${origin}/console/overview`;
}

export function recoveryRedirect(origin) {
  return `${origin}/console/reset-password`;
}

export function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

export function validatePassword(password, confirmation) {
  if (password.length < MIN_PASSWORD_LENGTH) return `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
  if (password !== confirmation) return 'Passwords do not match.';
  return '';
}

export function isRecoveryLink(location) {
  const query = new URLSearchParams(location.search);
  const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
  return query.get('type') === 'recovery' || hash.get('type') === 'recovery';
}
