-- Anonymous Supabase Auth sessions use the authenticated Postgres role.
-- Fiducaro organizations require a permanent user with a confirmed email.
-- Keep the hosted Auth "Confirm email" setting enabled for actual verification.
create or replace function private.member_role(p_organization_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select role from public.organization_members
  where organization_id = p_organization_id
    and user_id = (select auth.uid())
    and coalesce((select (auth.jwt()->>'is_anonymous')::boolean), false) is false
    and exists (
      select 1 from auth.users as human
      where human.id = (select auth.uid())
        and human.email is not null
        and human.email_confirmed_at is not null
    )
  limit 1;
$$;

create or replace function public.create_demo_organization(p_name text default 'Acme Corp')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='28000'; end if;
  if coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then
    raise exception 'A permanent human account is required' using errcode='42501';
  end if;
  if not exists (
    select 1 from auth.users as human
    where human.id = auth.uid()
      and human.email is not null
      and human.email_confirmed_at is not null
  ) then
    raise exception 'A confirmed email account is required' using errcode='42501';
  end if;
  if length(trim(p_name)) not between 2 and 100 then raise exception 'Invalid organization name'; end if;
  insert into public.organizations(name,created_by) values(trim(p_name),auth.uid()) returning id into v_org;
  insert into public.organization_members(organization_id,user_id,role) values(v_org,auth.uid(),'owner');
  perform private.seed_demo(v_org);
  return v_org;
end;
$$;

revoke all on function private.member_role(uuid) from public, anon, authenticated;
revoke all on function public.create_demo_organization(text) from public, anon;
grant execute on function public.create_demo_organization(text) to authenticated;
