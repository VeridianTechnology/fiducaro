-- RLS policies call private.is_member as authenticated. Its SECURITY DEFINER
-- body, and the privileged Console RPC, call private.member_role as their owner.
-- Authenticated clients do not need to execute member_role directly.
revoke all on function private.member_role(uuid) from authenticated;
