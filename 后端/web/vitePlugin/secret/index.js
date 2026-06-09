export function AddSecret(secret) {
  if (!secret) {
    secret = ''
  }
  global['heyu-secret'] = secret
}
