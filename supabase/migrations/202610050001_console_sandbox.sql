-- Fiducaro Console sandbox schema. All amounts and actions here are simulated.
-- Do not connect this schema to live assets or treat balances as a financial ledger.
create schema if not exists private;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 100),
  mode text not null default 'sandbox' check (mode = 'sandbox'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','operator','developer','auditor')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table if not exists public.treasuries (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  balance numeric(20,2) not null default 0 check (balance >= 0),
  reserve numeric(20,2) not null default 0 check (reserve >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.agents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  public_id text not null unique default ('agt_' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  name text not null check (length(trim(name)) between 2 and 100),
  purpose text not null default 'General operations',
  status text not null default 'Active' check (status in ('Active','Suspended')),
  balance numeric(20,2) not null default 0 check (balance >= 0),
  spent_30d numeric(20,2) not null default 0 check (spent_30d >= 0),
  created_at timestamptz not null default now(),
  unique (organization_id, id)
);

create table if not exists public.policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_id uuid not null unique,
  public_id text not null unique default ('pol_' || lower(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  daily_limit numeric(20,2) not null check (daily_limit > 0),
  transaction_limit numeric(20,2) not null check (transaction_limit > 0),
  approval_above numeric(20,2) not null check (approval_above > 0),
  vendors text[] not null default '{}',
  assets text[] not null default array['USDC'],
  privacy_mode text not null default 'Selective disclosure' check (privacy_mode in ('Public','Selective disclosure','Enhanced','Private settlement (planned)')),
  geography text not null default 'US, EU',
  updated_at timestamptz not null default now(),
  foreign key (organization_id, agent_id) references public.agents(organization_id, id) on delete cascade
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique default ('pay_' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_id uuid not null,
  vendor text not null,
  amount numeric(20,2) not null check (amount > 0),
  asset text not null,
  status text not null check (status in ('Completed','Review','Blocked','Rejected')),
  reason text,
  created_at timestamptz not null default now(),
  foreign key (organization_id, agent_id) references public.agents(organization_id, id) on delete cascade,
  unique (organization_id, id)
);

create table if not exists public.approvals (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique default ('apr_' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payment_id uuid not null unique,
  agent_id uuid not null,
  status text not null default 'Pending' check (status in ('Pending','Approved','Rejected')),
  reason text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id),
  foreign key (organization_id, payment_id) references public.payments(organization_id, id) on delete cascade,
  foreign key (organization_id, agent_id) references public.agents(organization_id, id) on delete cascade
);

create table if not exists public.activity_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_id uuid,
  actor_user_id uuid references auth.users(id),
  actor_kind text not null check (actor_kind in ('OPERATOR','AGENT','POLICY','SYSTEM')),
  action text not null,
  subject text not null,
  detail text not null default '',
  tone text not null default 'cyan' check (tone in ('cyan','green','amber','red')),
  created_at timestamptz not null default now(),
  foreign key (agent_id) references public.agents(id) on delete set null
);

create table if not exists public.webhooks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  url text not null check (url ~* '^https://'),
  status text not null default 'Demo only' check (status = 'Demo only'),
  created_at timestamptz not null default now()
);

create table if not exists public.api_credentials (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_id uuid not null,
  label text not null,
  suffix text not null,
  status text not null default 'Active' check (status in ('Active','Revoked')),
  created_at timestamptz not null default now(),
  foreign key (organization_id, agent_id) references public.agents(organization_id, id) on delete cascade
);

create index if not exists agents_org_idx on public.agents(organization_id);
create index if not exists payments_org_created_idx on public.payments(organization_id, created_at desc);
create index if not exists approvals_org_status_idx on public.approvals(organization_id, status);
create index if not exists events_org_created_idx on public.activity_events(organization_id, created_at desc);

-- Membership checks deliberately live outside the exposed public schema.
create or replace function private.member_role(p_organization_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select role from public.organization_members
  where organization_id = p_organization_id and user_id = (select auth.uid())
  limit 1;
$$;

create or replace function private.is_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.member_role(p_organization_id) is not null;
$$;

-- The exposed tables are read-only to authenticated clients. Mutations use guarded RPCs.
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.treasuries enable row level security;
alter table public.agents enable row level security;
alter table public.policies enable row level security;
alter table public.payments enable row level security;
alter table public.approvals enable row level security;
alter table public.activity_events enable row level security;
alter table public.webhooks enable row level security;
alter table public.api_credentials enable row level security;

revoke all on public.organizations, public.organization_members, public.treasuries,
  public.agents, public.policies, public.payments, public.approvals,
  public.activity_events, public.webhooks, public.api_credentials from anon, authenticated;
grant select on public.organizations, public.organization_members, public.treasuries,
  public.agents, public.policies, public.payments, public.approvals,
  public.activity_events, public.webhooks, public.api_credentials to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.member_role(uuid), private.is_member(uuid) to authenticated;

create policy organizations_member_read on public.organizations for select to authenticated
  using (private.is_member(id));
create policy members_member_read on public.organization_members for select to authenticated
  using (private.is_member(organization_id));
create policy treasuries_member_read on public.treasuries for select to authenticated
  using (private.is_member(organization_id));
create policy agents_member_read on public.agents for select to authenticated
  using (private.is_member(organization_id));
create policy policies_member_read on public.policies for select to authenticated
  using (private.is_member(organization_id));
create policy payments_member_read on public.payments for select to authenticated
  using (private.is_member(organization_id));
create policy approvals_member_read on public.approvals for select to authenticated
  using (private.is_member(organization_id));
create policy events_member_read on public.activity_events for select to authenticated
  using (private.is_member(organization_id));
create policy webhooks_member_read on public.webhooks for select to authenticated
  using (private.is_member(organization_id));
create policy credentials_member_read on public.api_credentials for select to authenticated
  using (private.is_member(organization_id));

create or replace function private.seed_demo(p_organization_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_agent uuid;
  v_payment uuid;
begin
  insert into public.treasuries(organization_id,balance,reserve)
  values (p_organization_id,2840000,500000)
  on conflict (organization_id) do update set balance=excluded.balance,reserve=excluded.reserve,updated_at=now();

  insert into public.agents(organization_id,name,purpose,balance,spent_30d)
  values (p_organization_id,'Procurement-07','Vendor procurement',18420,12840) returning id into v_agent;
  insert into public.policies(organization_id,agent_id,public_id,daily_limit,transaction_limit,approval_above,vendors,assets,privacy_mode)
  values (p_organization_id,v_agent,'pol_procurement_'||substr(replace(v_agent::text,'-',''),1,6),5000,1000,750,array['AWS','Anthropic','OpenAI'],array['USDC','ETH'],'Enhanced');
  insert into public.payments(organization_id,agent_id,vendor,amount,asset,status,reason)
  values (p_organization_id,v_agent,'AWS',880,'USDC','Review','Inference services') returning id into v_payment;
  insert into public.approvals(organization_id,payment_id,agent_id,reason)
  values (p_organization_id,v_payment,v_agent,'Inference services');
  insert into public.payments(organization_id,agent_id,vendor,amount,asset,status)
  values (p_organization_id,v_agent,'OpenAI',145,'USDC','Completed');
  insert into public.api_credentials(organization_id,agent_id,label,suffix)
  values (p_organization_id,v_agent,'Procurement sandbox','•••• 7C21');

  insert into public.agents(organization_id,name,purpose,balance,spent_30d)
  values (p_organization_id,'Research-04','Datasets and research',12450,3680) returning id into v_agent;
  insert into public.policies(organization_id,agent_id,daily_limit,transaction_limit,approval_above,vendors,assets)
  values (p_organization_id,v_agent,3000,500,400,array['OpenAI','Anthropic','AWS','DataHub'],array['USDC']);
  insert into public.payments(organization_id,agent_id,vendor,amount,asset,status)
  values (p_organization_id,v_agent,'DataHub',240,'USDC','Completed');

  insert into public.agents(organization_id,name,purpose,balance,spent_30d)
  values (p_organization_id,'Compute-02','Compute resources',36000,27200) returning id into v_agent;
  insert into public.policies(organization_id,agent_id,daily_limit,transaction_limit,approval_above,vendors,assets)
  values (p_organization_id,v_agent,12000,4000,2500,array['AWS','NVIDIA Cloud','Google Cloud'],array['USDC','ETH']);
  insert into public.payments(organization_id,agent_id,vendor,amount,asset,status,reason)
  values (p_organization_id,v_agent,'NVIDIA Cloud',3000,'USDC','Review','GPU compute') returning id into v_payment;
  insert into public.approvals(organization_id,payment_id,agent_id,reason)
  values (p_organization_id,v_payment,v_agent,'GPU compute');
  insert into public.payments(organization_id,agent_id,vendor,amount,asset,status)
  values (p_organization_id,v_agent,'AWS',1950,'USDC','Completed');

  insert into public.agents(organization_id,name,purpose,balance,spent_30d)
  values (p_organization_id,'Operations-03','Software subscriptions',7850,1950) returning id into v_agent;
  insert into public.policies(organization_id,agent_id,daily_limit,transaction_limit,approval_above,vendors,assets)
  values (p_organization_id,v_agent,1500,500,300,array['OpenAI','Google Cloud','Anthropic'],array['USDC']);

  insert into public.agents(organization_id,name,purpose,status,balance,spent_30d)
  values (p_organization_id,'Logistics-01','Shipping operations','Suspended',9500,2100) returning id into v_agent;
  insert into public.policies(organization_id,agent_id,daily_limit,transaction_limit,approval_above,vendors,assets)
  values (p_organization_id,v_agent,2500,800,600,array['DHL','FedEx'],array['USDC']);

  insert into public.activity_events(organization_id,actor_kind,action,subject,detail,tone)
  values
    (p_organization_id,'POLICY','human_review.required','Compute-02','$3,000 USDC · NVIDIA Cloud','amber'),
    (p_organization_id,'POLICY','human_review.required','Procurement-07','$880 USDC · AWS','amber'),
    (p_organization_id,'AGENT','payment.completed','Research-04','$240 USDC · DataHub','green'),
    (p_organization_id,'AGENT','payment.completed','Procurement-07','$145 USDC · OpenAI','green');
end;
$$;

create or replace function public.create_demo_organization(p_name text default 'Acme Corp')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if length(trim(p_name)) not between 2 and 100 then raise exception 'Invalid organization name'; end if;
  insert into public.organizations(name,created_by) values(trim(p_name),auth.uid()) returning id into v_org;
  insert into public.organization_members(organization_id,user_id,role) values(v_org,auth.uid(),'owner');
  perform private.seed_demo(v_org);
  return v_org;
end;
$$;

create or replace function public.console_sandbox_action(p_organization_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_role text;
  v_agent public.agents%rowtype;
  v_policy public.policies%rowtype;
  v_payment public.payments%rowtype;
  v_approval public.approvals%rowtype;
  v_amount numeric(20,2);
  v_vendor text;
  v_asset text;
  v_reason text;
  v_status text;
  v_agent_id uuid;
  v_id uuid;
  v_spent_today numeric(20,2);
  v_result text;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
  v_role := private.member_role(p_organization_id);
  if v_role is null or v_role not in ('owner','operator') then raise exception 'Insufficient organization role' using errcode='42501'; end if;
  if not exists(select 1 from public.organizations where id=p_organization_id and mode='sandbox') then raise exception 'Sandbox organization not found'; end if;
  if p_action = 'create_agent' then
    v_amount := (p_payload->>'balance')::numeric;
    if v_amount < 0 or v_amount is null then raise exception 'Invalid balance'; end if;
    if length(trim(coalesce(p_payload->>'name',''))) not between 2 and 100 then raise exception 'Invalid agent name'; end if;
    if (p_payload->>'dailyLimit')::numeric <= 0 or (p_payload->>'transactionLimit')::numeric <= 0 or (p_payload->>'approvalAbove')::numeric <= 0 then raise exception 'Invalid limits'; end if;
    update public.treasuries set balance=balance-v_amount,updated_at=now()
      where organization_id=p_organization_id and balance>=v_amount;
    if not found then raise exception 'Insufficient treasury balance'; end if;
    insert into public.agents(organization_id,name,purpose,balance)
      values(p_organization_id,trim(p_payload->>'name'),coalesce(nullif(trim(p_payload->>'purpose'),''),'General operations'),v_amount)
      returning id into v_agent_id;
    insert into public.policies(organization_id,agent_id,daily_limit,transaction_limit,approval_above,vendors)
      values(p_organization_id,v_agent_id,(p_payload->>'dailyLimit')::numeric,(p_payload->>'transactionLimit')::numeric,(p_payload->>'approvalAbove')::numeric,
      array(select jsonb_array_elements_text(coalesce(p_payload->'vendors','[]'::jsonb))));
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail)
      values(p_organization_id,v_agent_id,auth.uid(),'OPERATOR','agent.created',trim(p_payload->>'name'),v_amount::text||' TEST-USDC allocated');
    return jsonb_build_object('agent_id',v_agent_id,'outcome','created');
  elsif p_action = 'fund_agent' then
    v_agent_id := (p_payload->>'agentId')::uuid;
    v_amount := (p_payload->>'amount')::numeric;
    if v_amount is null or v_amount <= 0 then raise exception 'Invalid amount'; end if;
    select * into v_agent from public.agents where id=v_agent_id and organization_id=p_organization_id for update;
    if not found then raise exception 'Agent not found'; end if;
    update public.treasuries set balance=balance-v_amount,updated_at=now()
      where organization_id=p_organization_id and balance>=v_amount;
    if not found then raise exception 'Insufficient treasury balance'; end if;
    update public.agents set balance=balance+v_amount where id=v_agent_id;
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail,tone)
      values(p_organization_id,v_agent_id,auth.uid(),'OPERATOR','account.funded',v_agent.name,v_amount::text||' TEST-USDC','green');
    return jsonb_build_object('outcome','funded');
  elsif p_action = 'change_status' then
    v_agent_id := (p_payload->>'agentId')::uuid;
    select * into v_agent from public.agents where id=v_agent_id and organization_id=p_organization_id for update;
    if not found then raise exception 'Agent not found'; end if;
    v_status := case when v_agent.status='Active' then 'Suspended' else 'Active' end;
    update public.agents set status=v_status where id=v_agent_id;
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail,tone)
      values(p_organization_id,v_agent_id,auth.uid(),'OPERATOR',case when v_status='Active' then 'account.reactivated' else 'account.frozen' end,v_agent.name,v_status,case when v_status='Active' then 'green' else 'amber' end);
    return jsonb_build_object('outcome',v_status);
  elsif p_action = 'save_policy' then
    v_agent_id := (p_payload->>'agentId')::uuid;
    select * into v_agent from public.agents where id=v_agent_id and organization_id=p_organization_id;
    if not found then raise exception 'Agent not found'; end if;
    update public.policies set
      daily_limit=(p_payload->>'dailyLimit')::numeric,
      transaction_limit=(p_payload->>'transactionLimit')::numeric,
      approval_above=(p_payload->>'approvalAbove')::numeric,
      vendors=array(select jsonb_array_elements_text(coalesce(p_payload->'vendors','[]'::jsonb))),
      assets=array(select jsonb_array_elements_text(coalesce(p_payload->'assets','[]'::jsonb))),
      privacy_mode=p_payload->>'privacy',geography=p_payload->>'geography',updated_at=now()
      where agent_id=v_agent_id and organization_id=p_organization_id;
    if not found then raise exception 'Policy not found'; end if;
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail)
      values(p_organization_id,v_agent_id,auth.uid(),'OPERATOR','policy.updated',v_agent.name,'Limits and permissions changed');
    return jsonb_build_object('outcome','updated');
  elsif p_action = 'set_privacy' then
    v_agent_id := (p_payload->>'agentId')::uuid;
    select * into v_agent from public.agents where id=v_agent_id and organization_id=p_organization_id;
    if not found then raise exception 'Agent not found'; end if;
    update public.policies set privacy_mode=p_payload->>'privacy',updated_at=now()
      where agent_id=v_agent_id and organization_id=p_organization_id;
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail)
      values(p_organization_id,v_agent_id,auth.uid(),'OPERATOR','privacy.updated',v_agent.name,p_payload->>'privacy');
    return jsonb_build_object('outcome','updated');
  elsif p_action = 'simulate_payment' then
    v_agent_id := (p_payload->>'agentId')::uuid;
    v_amount := (p_payload->>'amount')::numeric;
    v_vendor := trim(coalesce(p_payload->>'vendor',''));
    v_asset := upper(trim(coalesce(p_payload->>'asset','')));
    if v_amount is null or v_amount <= 0 or v_vendor='' then raise exception 'Invalid payment request'; end if;
    select * into v_agent from public.agents where id=v_agent_id and organization_id=p_organization_id for update;
    if not found then raise exception 'Agent not found'; end if;
    select * into v_policy from public.policies where agent_id=v_agent_id and organization_id=p_organization_id;
    if not found then raise exception 'Policy not found'; end if;
    select coalesce(sum(amount),0) into v_spent_today from public.payments
      where agent_id=v_agent_id and organization_id=p_organization_id and status='Completed' and created_at::date=current_date;
    v_reason := null;
    if v_agent.status<>'Active' then v_reason:='Agent account is suspended';
    elsif not (v_asset = any(v_policy.assets)) then v_reason:='Asset is not allowed';
    elsif not exists(select 1 from unnest(v_policy.vendors) approved where lower(approved)=lower(v_vendor)) then v_reason:='Counterparty is not approved';
    elsif v_amount>v_agent.balance then v_reason:='Insufficient agent balance';
    elsif v_amount>v_policy.transaction_limit then v_reason:='Transaction limit exceeded';
    elsif v_spent_today+v_amount>v_policy.daily_limit then v_reason:='Daily limit exceeded';
    end if;
    if v_reason is not null then v_result:='Blocked';
    elsif v_amount>v_policy.approval_above then v_result:='Review';
    else v_result:='Completed'; end if;
    insert into public.payments(organization_id,agent_id,vendor,amount,asset,status,reason)
      values(p_organization_id,v_agent_id,v_vendor,v_amount,v_asset,v_result,coalesce(v_reason,nullif(trim(p_payload->>'memo'),'')))
      returning * into v_payment;
    if v_result='Review' then
      insert into public.approvals(organization_id,payment_id,agent_id,reason)
        values(p_organization_id,v_payment.id,v_agent_id,coalesce(nullif(trim(p_payload->>'memo'),''),'Sandbox payment'));
    elsif v_result='Completed' then
      update public.agents set balance=balance-v_amount,spent_30d=spent_30d+v_amount where id=v_agent_id;
    end if;
    insert into public.activity_events(organization_id,agent_id,actor_kind,action,subject,detail,tone)
      values(p_organization_id,v_agent_id,case when v_result='Completed' then 'AGENT' else 'POLICY' end,
        case when v_result='Completed' then 'payment.completed' when v_result='Review' then 'human_review.required' else 'policy.denied' end,
        v_agent.name,v_amount::text||' '||v_asset||' · '||v_vendor||coalesce(' · '||v_reason,''),
        case when v_result='Completed' then 'green' when v_result='Review' then 'amber' else 'red' end);
    return jsonb_build_object('outcome',v_result,'reason',v_reason,'payment_id',v_payment.id);
  elsif p_action = 'resolve_approval' then
    v_id := (p_payload->>'approvalId')::uuid;
    select * into v_approval from public.approvals where id=v_id and organization_id=p_organization_id for update;
    if not found or v_approval.status<>'Pending' then raise exception 'Approval is no longer pending'; end if;
    select * into v_payment from public.payments where id=v_approval.payment_id and organization_id=p_organization_id for update;
    select * into v_agent from public.agents where id=v_approval.agent_id and organization_id=p_organization_id for update;
    if (p_payload->>'approve')::boolean then
      if v_agent.status<>'Active' or v_agent.balance<v_payment.amount then raise exception 'Account unavailable or balance too low'; end if;
      update public.agents set balance=balance-v_payment.amount,spent_30d=spent_30d+v_payment.amount where id=v_agent.id;
      v_status:='Approved';
      update public.payments set status='Completed' where id=v_payment.id;
    else
      v_status:='Rejected';
      update public.payments set status='Rejected' where id=v_payment.id;
    end if;
    update public.approvals set status=v_status,resolved_at=now(),resolved_by=auth.uid() where id=v_id;
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail,tone)
      values(p_organization_id,v_agent.id,auth.uid(),'OPERATOR',case when v_status='Approved' then 'approval.granted' else 'approval.rejected' end,
        v_agent.name,v_payment.amount::text||' '||v_payment.asset||' · '||v_payment.vendor,
        case when v_status='Approved' then 'green' else 'red' end);
    return jsonb_build_object('outcome',v_status);
  elsif p_action in ('create_key','rotate_key','revoke_key') then
    if p_action='create_key' then
      v_agent_id := (p_payload->>'agentId')::uuid;
      select * into v_agent from public.agents where id=v_agent_id and organization_id=p_organization_id;
      if not found then raise exception 'Agent not found'; end if;
      if length(trim(coalesce(p_payload->>'label',''))) < 2 then raise exception 'Credential label required'; end if;
      insert into public.api_credentials(organization_id,agent_id,label,suffix)
        values(p_organization_id,v_agent_id,trim(p_payload->>'label'),p_payload->>'suffix');
      v_status:='credential.created';
    else
      v_id := (p_payload->>'keyId')::uuid;
      select agent_id into v_agent_id from public.api_credentials where id=v_id and organization_id=p_organization_id;
      if not found then raise exception 'Credential not found'; end if;
      if p_action='rotate_key' then
        update public.api_credentials set suffix=p_payload->>'suffix' where id=v_id and status='Active';
        if not found then raise exception 'Credential is not active'; end if;
        v_status:='credential.rotated';
      else
        update public.api_credentials set status='Revoked' where id=v_id;
        v_status:='credential.revoked';
      end if;
    end if;
    insert into public.activity_events(organization_id,agent_id,actor_user_id,actor_kind,action,subject,detail)
      values(p_organization_id,v_agent_id,auth.uid(),'OPERATOR',v_status,
        (select name from public.agents where id=v_agent_id),coalesce(p_payload->>'label','Demo credential'));
    return jsonb_build_object('outcome',v_status);
  elsif p_action = 'add_webhook' then
    if coalesce(p_payload->>'url','') !~* '^https://' then raise exception 'HTTPS URL required'; end if;
    insert into public.webhooks(organization_id,url) values(p_organization_id,p_payload->>'url');
    insert into public.activity_events(organization_id,actor_user_id,actor_kind,action,subject,detail)
      values(p_organization_id,auth.uid(),'OPERATOR','webhook.configured','Organization',p_payload->>'url');
    return jsonb_build_object('outcome','created');
  elsif p_action = 'reset_demo' then
    if v_role<>'owner' then raise exception 'Owner role required' using errcode='42501'; end if;
    delete from public.activity_events where organization_id=p_organization_id;
    delete from public.webhooks where organization_id=p_organization_id;
    delete from public.api_credentials where organization_id=p_organization_id;
    delete from public.agents where organization_id=p_organization_id;
    perform private.seed_demo(p_organization_id);
    return jsonb_build_object('outcome','reset');
  end if;
  raise exception 'Unsupported sandbox action';
end;
$$;

revoke all on function public.create_demo_organization(text), public.console_sandbox_action(uuid,text,jsonb) from public, anon;
grant execute on function public.create_demo_organization(text), public.console_sandbox_action(uuid,text,jsonb) to authenticated;
revoke all on function private.seed_demo(uuid) from public, anon, authenticated;
