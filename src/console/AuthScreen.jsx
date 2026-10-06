import React, { useState } from 'react';
import { ArrowRight, Fingerprint, LockKeyhole, Mail, ShieldCheck } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { MIN_PASSWORD_LENGTH, consoleRedirect, recoveryRedirect, validateEmail, validatePassword } from './authFlow';

export function AuthFrame({ icon: Icon = Fingerprint, title, description, children }) {
  return <div className="con-auth-page"><div className="con-auth-card">
    <a className="con-auth-brand" href="/"><span className="brand-mark"/> FIDUCARO</a>
    <div className="con-auth-icon"><Icon size={27}/></div>
    <span className="con-kicker">HUMAN CONTROL PLANE</span>
    <h1>{title}</h1><p>{description}</p>{children}
  </div></div>;
}

export function AuthScreen() {
  const [view, setView] = useState('signin');
  const [signInMethod, setSignInMethod] = useState('password');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [sentEmail, setSentEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  function show(viewName) {
    setView(viewName);
    setPassword(''); setConfirmation(''); setError(''); setMessage('');
  }

  async function submit(event) {
    event.preventDefault();
    const address = email.trim().toLowerCase();
    if (!validateEmail(address)) { setError('Enter a valid email address.'); return; }
    if (view === 'signup') {
      const validation = validatePassword(password, confirmation);
      if (validation) { setError(validation); return; }
    }
    setBusy(true); setError(''); setMessage('');
    try {
      if (view === 'signup') {
        const { data, error: authError } = await supabase.auth.signUp({
          email: address, password,
          options: { emailRedirectTo: consoleRedirect(window.location.origin) },
        });
        if (authError) throw authError;
        if (data.session) {
          await supabase.auth.signOut();
          throw new Error('Email confirmation is disabled in Supabase Auth. Enable it before completing registration.');
        }
        setSentEmail(address);
        show('checkEmail');
      } else if (view === 'forgot') {
        const { error: authError } = await supabase.auth.resetPasswordForEmail(address, {
          redirectTo: recoveryRedirect(window.location.origin),
        });
        if (authError) throw authError;
        setSentEmail(address);
        show('resetSent');
      } else if (signInMethod === 'link') {
        const { error: authError } = await supabase.auth.signInWithOtp({
          email: address,
          options: { shouldCreateUser: false, emailRedirectTo: consoleRedirect(window.location.origin) },
        });
        if (authError) throw authError;
        setMessage('If this account exists, check your email for a sign-in link.');
      } else {
        const { error: authError } = await supabase.auth.signInWithPassword({ email: address, password });
        if (authError) throw authError;
      }
    } catch (authError) { setError(authError.message || 'Authentication failed.'); }
    finally { setBusy(false); }
  }

  async function resendConfirmation() {
    setBusy(true); setError(''); setMessage('');
    try {
      const { error: authError } = await supabase.auth.resend({
        type: 'signup', email: sentEmail,
        options: { emailRedirectTo: consoleRedirect(window.location.origin) },
      });
      if (authError) throw authError;
      setMessage('Confirmation email sent again.');
    } catch (authError) { setError(authError.message || 'Could not resend confirmation.'); }
    finally { setBusy(false); }
  }

  if (view === 'checkEmail') return <AuthFrame icon={Mail} title="Check your email" description={<>We sent a confirmation link to <strong className="con-auth-email">{sentEmail}</strong> Confirm your email to activate your Fiducaro account.</>}>
    <div className="con-auth-actions"><button type="button" className="con-auth-secondary" onClick={() => show('signin')}>Back to Sign In</button><button type="button" className="con-auth-secondary" disabled={busy} onClick={resendConfirmation}>{busy ? 'Sending…' : 'Resend confirmation'}</button></div>
    {error && <div className="con-auth-message error" role="alert">{error}</div>}{message && <div className="con-auth-message" role="status">{message}</div>}
  </AuthFrame>;

  if (view === 'resetSent') return <AuthFrame icon={Mail} title="Check your email" description={<>If an account exists for <strong className="con-auth-email">{sentEmail}</strong>, we sent a password reset link. Follow it to set a new password.</>}>
    <div className="con-auth-actions"><button type="button" className="con-auth-secondary" onClick={() => show('signin')}>Back to Sign In</button><button type="button" className="con-auth-secondary" onClick={() => show('forgot')}>Send another link</button></div>
  </AuthFrame>;

  const signup = view === 'signup';
  const forgot = view === 'forgot';
  return <AuthFrame title={signup ? 'Create your Fiducaro account' : forgot ? 'Reset your password' : 'Sign in to the Console.'} description={signup ? 'Create a human account to govern your sandbox organization.' : forgot ? 'Enter your email and we’ll send a password reset link.' : 'Operators configure financial authority. Agents connect through a separate API.'}>
    {!forgot && <div className="con-auth-tabs"><button type="button" className={!signup ? 'selected' : ''} onClick={() => show('signin')}>Sign In</button><button type="button" className={signup ? 'selected' : ''} onClick={() => show('signup')}>Create Account</button></div>}
    {!signup && !forgot && <div className="con-auth-methods"><button type="button" className={signInMethod === 'password' ? 'selected' : ''} onClick={() => { setSignInMethod('password'); setError(''); }}>Password</button><button type="button" className={signInMethod === 'link' ? 'selected' : ''} onClick={() => { setSignInMethod('link'); setError(''); }}>Email link</button></div>}
    <form onSubmit={submit}>
      <label>Email<input type="email" value={email} onChange={event => setEmail(event.target.value)} required autoComplete="email" placeholder="you@organization.com"/></label>
      {(signup || (!forgot && signInMethod === 'password')) && <label>Password<input type="password" value={password} onChange={event => setPassword(event.target.value)} required minLength={signup ? MIN_PASSWORD_LENGTH : undefined} autoComplete={signup ? 'new-password' : 'current-password'}/></label>}
      {signup && <label>Confirm Password<input type="password" value={confirmation} onChange={event => setConfirmation(event.target.value)} required autoComplete="new-password"/></label>}
      {!signup && !forgot && signInMethod === 'password' && <button type="button" className="con-auth-inline" onClick={() => show('forgot')}>Forgot password?</button>}
      <button type="submit" disabled={busy}>{busy ? 'Please wait…' : signup ? 'Create Account' : forgot ? 'Send reset link' : signInMethod === 'link' ? 'Send sign-in link' : 'Sign In'} <ArrowRight size={16}/></button>
    </form>
    {forgot && <button type="button" className="con-auth-inline con-auth-back" onClick={() => show('signin')}>Back to Sign In</button>}
    {error && <div className="con-auth-message error" role="alert">{error}</div>}{message && <div className="con-auth-message" role="status">{message}</div>}
    <div className="con-auth-foot"><LockKeyhole size={15}/> Human accounts only. No agent uses a human login.</div>
  </AuthFrame>;
}

export function PasswordRecovery({ session, onDone }) {
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');

  async function submit(event) {
    event.preventDefault();
    const validation = validatePassword(password, confirmation);
    if (validation) { setError(validation); return; }
    setBusy(true); setError('');
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) throw signOutError;
      setDone(true);
    } catch (authError) { setError(authError.message || 'Could not update password.'); }
    finally { setBusy(false); }
  }

  if (done) return <AuthFrame icon={ShieldCheck} title="Password updated" description="Your password has been changed. Sign in with your new password to continue."><button type="button" className="con-auth-secondary" onClick={onDone}>Back to Sign In</button></AuthFrame>;
  if (!session) return <AuthFrame icon={LockKeyhole} title="Reset link unavailable" description="This reset link is invalid or expired. Request a new link from the sign-in screen."><button type="button" className="con-auth-secondary" onClick={onDone}>Back to Sign In</button></AuthFrame>;
  return <AuthFrame icon={LockKeyhole} title="Set a new password" description="Choose a new password for your Fiducaro account."><form onSubmit={submit}>
    <label>New Password<input type="password" value={password} onChange={event => setPassword(event.target.value)} required minLength={MIN_PASSWORD_LENGTH} autoComplete="new-password"/></label>
    <label>Confirm Password<input type="password" value={confirmation} onChange={event => setConfirmation(event.target.value)} required autoComplete="new-password"/></label>
    <button type="submit" disabled={busy}>{busy ? 'Updating…' : 'Update password'} <ArrowRight size={16}/></button>
  </form>{error && <div className="con-auth-message error" role="alert">{error}</div>}</AuthFrame>;
}
