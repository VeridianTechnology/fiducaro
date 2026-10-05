-- Match developer permissions to demo credential and webhook controls, and
-- recheck current policy before releasing a held sandbox payment.
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
  if v_role is null or (v_role not in ('owner','operator') and not (v_role='developer' and p_action in ('create_key','rotate_key','revoke_key','add_webhook'))) then
    raise exception 'Insufficient organization role' using errcode='42501';
  end if;
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
      select * into v_policy from public.policies where agent_id=v_agent.id and organization_id=p_organization_id;
      if not found then raise exception 'Policy not found'; end if;
      select coalesce(sum(amount),0) into v_spent_today from public.payments
        where agent_id=v_agent.id and organization_id=p_organization_id and status='Completed' and created_at::date=current_date;
      if not (v_payment.asset = any(v_policy.assets))
        or not exists(select 1 from unnest(v_policy.vendors) approved where lower(approved)=lower(v_payment.vendor))
        or v_payment.amount>v_policy.transaction_limit
        or v_spent_today+v_payment.amount>v_policy.daily_limit then
        raise exception 'Payment no longer meets current policy';
      end if;
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
