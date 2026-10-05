import React, { useEffect, useState } from 'react';
import { ArrowRight, CheckCircle2, Fingerprint, LockKeyhole, Mail, ShieldCheck, TestTube2 } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { createDemoOrganization, listOrganizations, loadConsoleData, runConsoleAction } from './repository';
import Console from './Console';
import './console.css';

function AuthScreen({ onSignedIn }) {
  const [method, setMethod] = useState('link');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  async function submit(event) {
    event.preventDefault();
    setBusy(true); setMessage('');
    try {
      if (method === 'link') {
        const { error } = await supabase.auth.signInWithOtp({ email: email.trim(), options: { shouldCreateUser: false, emailRedirectTo: `${window.location.origin}/console/overview` } });
        if (error) throw error;
        setMessage('If this address was invited, check your email for a sign-in link.');
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw error;
        onSignedIn();
      }
    } catch (error) { setMessage(error.message || 'Sign-in failed.'); }
    finally { setBusy(false); }
  }
  return <div className="con-auth-page"><div className="con-auth-card"><a className="con-auth-brand" href="/"><span className="brand-mark"/> FIDUCARO</a><div className="con-auth-icon"><Fingerprint size={27}/></div><span className="con-kicker">HUMAN CONTROL PLANE</span><h1>Sign in to the Console.</h1><p>Operators configure financial authority. Agents connect through a separate API.</p><div className="con-auth-tabs"><button className={method==='link'?'selected':''} onClick={()=>setMethod('link')}>Email link</button><button className={method==='password'?'selected':''} onClick={()=>setMethod('password')}>Password</button></div><form onSubmit={submit}><label>Email address<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email" placeholder="you@organization.com"/></label>{method==='password'&&<label>Password<input type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="current-password"/></label>}<button type="submit" disabled={busy}>{busy?'Please wait…':method==='link'?'Send sign-in link':'Sign in'} <ArrowRight size={16}/></button></form>{message&&<div className="con-auth-message" role="status">{message}</div>}<div className="con-auth-foot"><LockKeyhole size={15}/> Invite-only access. No agent uses a human login.</div></div></div>;
}

function Onboarding({ email, onCreate, busy, error }) {
  const [name, setName] = useState('Acme Corp');
  return <div className="con-auth-page"><div className="con-auth-card"><a className="con-auth-brand" href="/"><span className="brand-mark"/> FIDUCARO</a><div className="con-auth-icon"><ShieldCheck size={27}/></div><span className="con-kicker">WELCOME / {email}</span><h1>Create your sandbox organization.</h1><p>Start with fictional TEST-USDC balances, five sample agents, policies, and approval requests. No real funds are involved.</p><form onSubmit={e=>{e.preventDefault();onCreate(name)}}><label>Organization name<input value={name} onChange={e=>setName(e.target.value)} minLength={2} maxLength={100} required/></label><button disabled={busy} type="submit">{busy?'Creating…':'Create demo organization'} <ArrowRight size={16}/></button></form>{error&&<div className="con-auth-message error" role="alert">{error}</div>}<div className="con-auth-foot"><TestTube2 size={15}/> Your organization will be stored in Supabase with member-scoped access.</div></div></div>;
}

export default function ConsoleGateway() {
  const [session, setSession] = useState(undefined);
  const [organizations, setOrganizations] = useState([]);
  const [organizationId, setOrganizationId] = useState('');
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    if (!supabase) { setSession(null); return; }
    let mounted = true;
    supabase.auth.getSession().then(({data: result})=>{if(mounted)setSession(result.session)}).catch(err=>{if(mounted){setError(err.message);setSession(null)}});
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession)=>{if(mounted)setSession(nextSession)});
    return ()=>{mounted=false;listener.subscription.unsubscribe()};
  }, []);
  useEffect(() => {
    if (!session) { setOrganizations([]); setData(null); return; }
    let active = true;
    setLoading(true); setError('');
    listOrganizations().then(rows => {
      if (!active) return;
      setOrganizations(rows);
      const remembered = sessionStorage.getItem('fiducaro-selected-org');
      setOrganizationId(current => rows.some(row=>row.id===current) ? current : rows.some(row=>row.id===remembered) ? remembered : rows[0]?.id || '');
    }).catch(err=>{if(active)setError(err.message)}).finally(()=>{if(active)setLoading(false)});
    return ()=>{active=false};
  }, [session?.user?.id]);
  useEffect(() => {
    if (!organizationId || !session) { setData(null); return; }
    const organization = organizations.find(item=>item.id===organizationId);
    if (!organization) return;
    let active = true;
    setLoading(true); setError('');
    sessionStorage.setItem('fiducaro-selected-org',organizationId);
    loadConsoleData(organization).then(result=>{if(active)setData(result)}).catch(err=>{if(active)setError(err.message)}).finally(()=>{if(active)setLoading(false)});
    return ()=>{active=false};
  }, [organizationId, organizations, session?.user?.id]);
  async function refresh() {
    const organization=organizations.find(item=>item.id===organizationId);
    if (!organization) return;
    setData(await loadConsoleData(organization));
  }
  async function createOrganization(name) {
    setLoading(true);setError('');
    try {
      const id=await createDemoOrganization(name);
      const rows=await listOrganizations();
      setOrganizations(rows);setOrganizationId(id);
    } catch(err) {setError(err.message)}
    finally {setLoading(false)}
  }
  async function action(name,payload) {
    if (!data) throw new Error('Organization data is not loaded.');
    const normalized={...payload};
    if (normalized.agentId) {
      const agent=data.agents.find(item=>item.id===normalized.agentId);
      if (!agent) throw new Error('Agent not found in this organization.');
      normalized.agentId=agent.dbId;
    }
    const result=await runConsoleAction(organizationId,name,normalized);
    await refresh();
    return result;
  }
  if (!supabase) return <div className="con-auth-page"><div className="con-auth-card"><h1>Supabase is not configured.</h1><p>Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to .env.local, then restart the dev server.</p></div></div>;
  if (session===undefined) return <div className="con-loading">Checking Console session…</div>;
  if (!session) return <AuthScreen onSignedIn={()=>{}}/>;
  if (loading && !data) return <div className="con-loading">Loading your organization…</div>;
  if (error && !organizations.length) return <div className="con-auth-page"><div className="con-auth-card"><h1>Console setup is incomplete.</h1><p>{error}</p><button className="con-auth-retry" onClick={()=>window.location.reload()}>Retry</button></div></div>;
  if (!organizations.length) return <Onboarding email={session.user.email} onCreate={createOrganization} busy={loading} error={error}/>;
  if (error && !data) return <div className="con-auth-page"><div className="con-auth-card"><h1>Could not load the Console.</h1><p>{error}</p><button className="con-auth-retry" onClick={()=>window.location.reload()}>Retry</button></div></div>;
  if (!data) return <div className="con-loading">Loading sandbox data…</div>;
  return <Console data={data} organizations={organizations} organizationId={organizationId} onSelectOrganization={id=>{setData(null);setOrganizationId(id)}} onAction={action} onSignOut={()=>supabase.auth.signOut()}/>;
}
