-- Membership helpers are callable only by signed-in clients. They are kept in
-- the non-exposed private schema and evaluate the caller's auth.uid().
revoke all on function private.member_role(uuid), private.is_member(uuid) from public, anon;
grant execute on function private.member_role(uuid), private.is_member(uuid) to authenticated;
