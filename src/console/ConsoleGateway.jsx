import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowRight, ShieldCheck, TestTube2 } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { isRecoveryLink } from './authFlow';
import { AuthScreen, PasswordRecovery } from './AuthScreen';
import { createDemoOrganization, listOrganizations, loadConsoleData, runConsoleAction } from './repository';
import Console from './Console';
import './console.css';

function Onboarding({ email, onCreate, busy, error }) {
  const [name, setName] = useState('');
  return <div className="con-auth-page"><div className="con-auth-card"><a className="con-auth-brand" href="/"><span className="brand-mark"/> FIDUCARO</a><div className="con-auth-icon"><ShieldCheck size={27}/></div><span className="con-kicker">WELCOME / {email}</span><h1>Create your organization</h1><p>Start with fictional TEST-USDC balances, five sample agents, policies, and approval requests. No real funds are involved.</p><form onSubmit={e=>{e.preventDefault();onCreate(name.trim())}}><label>Organization name<input value={name} onChange={e=>setName(e.target.value)} minLength={2} maxLength={100} required/></label><button disabled={busy} type="submit">{busy?'Creating…':'Create organization'} <ArrowRight size={16}/></button></form>{error&&<div className="con-auth-message error" role="alert">{error}</div>}<div className="con-auth-foot"><TestTube2 size={15}/> Your organization will be stored in Supabase with member-scoped access.</div></div></div>;
}

export default function ConsoleGateway() {
  const navigate = useNavigate();
  const [session, setSession] = useState(undefined);
  const [recoveryMode, setRecoveryMode] = useState(() => window.location.pathname.endsWith('/reset-password') || isRecoveryLink(window.location));
  const [organizations, setOrganizations] = useState([]);
  const [organizationId, setOrganizationId] = useState('');
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [signOutError, setSignOutError] = useState('');
  useEffect(() => {
    if (!supabase) { setSession(null); return; }
    let mounted = true;
    supabase.auth.getSession().then(({data: result})=>{if(mounted)setSession(result.session)}).catch(err=>{if(mounted){setError(err.message);setSession(null)}});
    const { data: listener } = supabase.auth.onAuthStateChange((event, nextSession)=>{if(mounted){if(event==='PASSWORD_RECOVERY')setRecoveryMode(true);setSession(nextSession)}});
    return ()=>{mounted=false;listener.subscription.unsubscribe()};
  }, []);
  useEffect(() => {
    if (session?.user?.is_anonymous) supabase.auth.signOut();
  }, [session?.user?.id, session?.user?.is_anonymous]);
  useEffect(() => {
    if (!session || session.user.is_anonymous || recoveryMode) { setOrganizations([]); setData(null); return; }
    let active = true;
    setLoading(true); setError('');
    listOrganizations().then(rows => {
      if (!active) return;
      setOrganizations(rows);
      const remembered = sessionStorage.getItem('fiducaro-selected-org');
      setOrganizationId(current => rows.some(row=>row.id===current) ? current : rows.some(row=>row.id===remembered) ? remembered : rows[0]?.id || '');
    }).catch(err=>{if(active)setError(err.message)}).finally(()=>{if(active)setLoading(false)});
    return ()=>{active=false};
  }, [session?.user?.id, recoveryMode]);
  useEffect(() => {
    if (!organizationId || !session || session.user.is_anonymous || recoveryMode) { setData(null); return; }
    const organization = organizations.find(item=>item.id===organizationId);
    if (!organization) return;
    let active = true;
    setLoading(true); setError('');
    sessionStorage.setItem('fiducaro-selected-org',organizationId);
    loadConsoleData(organization).then(result=>{if(active)setData(result)}).catch(err=>{if(active)setError(err.message)}).finally(()=>{if(active)setLoading(false)});
    return ()=>{active=false};
  }, [organizationId, organizations, session?.user?.id, recoveryMode]);
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
      navigate('/console/overview', { replace: true });
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
  async function signOut() {
    setSignOutError('');
    const { error: authError } = await supabase.auth.signOut();
    if (authError) { setSignOutError(authError.message); return; }
    sessionStorage.removeItem('fiducaro-selected-org');
    setOrganizations([]);setOrganizationId('');setData(null);setSession(null);
  }
  if (!supabase) return <div className="con-auth-page"><div className="con-auth-card"><h1>Supabase is not configured.</h1><p>Add VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to .env.local, then restart the dev server.</p></div></div>;
  if (session===undefined) return <div className="con-loading">Checking Console session…</div>;
  if (recoveryMode) return <PasswordRecovery session={session} onDone={()=>{navigate('/console/overview', { replace: true });setRecoveryMode(false)}}/>;
  if (!session || session.user.is_anonymous) return <AuthScreen/>;
  if (loading && !data) return <div className="con-loading">Loading your organization…</div>;
  if (error && !organizations.length) return <div className="con-auth-page"><div className="con-auth-card"><h1>Console setup is incomplete.</h1><p>{error}</p><button className="con-auth-retry" onClick={()=>window.location.reload()}>Retry</button></div></div>;
  if (!organizations.length) return <Onboarding email={session.user.email} onCreate={createOrganization} busy={loading} error={error}/>;
  if (error && !data) return <div className="con-auth-page"><div className="con-auth-card"><h1>Could not load the Console.</h1><p>{error}</p><button className="con-auth-retry" onClick={()=>window.location.reload()}>Retry</button></div></div>;
  if (!data) return <div className="con-loading">Loading sandbox data…</div>;
  return <><Console data={data} organizations={organizations} organizationId={organizationId} onSelectOrganization={id=>{setData(null);setOrganizationId(id)}} onAction={action} onSignOut={signOut}/>{signOutError&&<div className="con-toast" role="alert">Sign-out failed: {signOutError}</div>}</>;
}
