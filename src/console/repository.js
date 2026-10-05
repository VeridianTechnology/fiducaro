import { supabase } from '../lib/supabase';

function assertResult(result) {
  if (result.error) throw result.error;
  return result.data;
}

export async function listOrganizations() {
  const rows = assertResult(await supabase.from('organization_members')
    .select('organization_id,role,organizations(id,name,mode)')
    .order('created_at', { ascending: true }));
  return rows.map(row => ({ id: row.organization_id, role: row.role, name: row.organizations?.name || 'Organization', mode: row.organizations?.mode || 'sandbox' }));
}

export async function createDemoOrganization(name) {
  return assertResult(await supabase.rpc('create_demo_organization', { p_name: name }));
}

export async function loadConsoleData(organization) {
  const orgId = organization.id;
  const names = ['treasuries','agents','policies','payments','approvals','activity_events','webhooks','api_credentials'];
  const results = await Promise.all(names.map(name => supabase.from(name).select('*').eq('organization_id', orgId)));
  const [treasuries,agents,policies,payments,approvals,events,webhooks,keys] = results.map(assertResult);
  const policyByAgent = new Map(policies.map(policy => [policy.agent_id, policy]));
  const agentByUuid = new Map(agents.map(agent => [agent.id, agent]));
  const approvalByPayment = new Map(approvals.map(approval => [approval.payment_id, approval]));
  return {
    organization: { id: orgId, name: organization.name, mode: organization.mode, treasury: Number(treasuries[0]?.balance || 0), reserve: Number(treasuries[0]?.reserve || 0), role: organization.role },
    agents: agents.map(agent => {
      const policy = policyByAgent.get(agent.id);
      return {
        id: agent.public_id,
        dbId: agent.id,
        name: agent.name,
        purpose: agent.purpose,
        status: agent.status,
        balance: Number(agent.balance),
        spent30d: Number(agent.spent_30d),
        policyId: policy?.public_id || 'No policy',
        policy: {
          dailyLimit: Number(policy?.daily_limit || 0),
          transactionLimit: Number(policy?.transaction_limit || 0),
          approvalAbove: Number(policy?.approval_above || 0),
          vendors: policy?.vendors || [],
          assets: policy?.assets || [],
          privacy: policy?.privacy_mode || 'Selective disclosure',
          geography: policy?.geography || 'US, EU',
        },
      };
    }).sort((a,b) => a.name.localeCompare(b.name)),
    payments: payments.map(payment => ({ id: payment.public_id, dbId: payment.id, agentId: agentByUuid.get(payment.agent_id)?.public_id || payment.agent_id, vendor: payment.vendor, amount: Number(payment.amount), asset: payment.asset, status: payment.status, approvalId: approvalByPayment.get(payment.id)?.id, createdAt: payment.created_at })).sort((a,b) => new Date(b.createdAt)-new Date(a.createdAt)),
    approvals: approvals.map(approval => {
      const payment = payments.find(item => item.id === approval.payment_id);
      return { id: approval.id, publicId: approval.public_id, agentId: agentByUuid.get(approval.agent_id)?.public_id || approval.agent_id, vendor: payment?.vendor || '', amount: Number(payment?.amount || 0), asset: payment?.asset || 'USDC', reason: approval.reason || payment?.reason || '', status: approval.status, createdAt: approval.created_at };
    }).sort((a,b) => new Date(b.createdAt)-new Date(a.createdAt)),
    events: events.map(item => ({ id: item.id, at: item.created_at, actor: item.actor_kind, action: item.action, subject: item.subject, detail: item.detail, tone: item.tone })).sort((a,b) => new Date(b.at)-new Date(a.at)),
    webhooks: webhooks.map(item => ({ id: item.id, url: item.url, status: item.status, createdAt: item.created_at })).sort((a,b) => new Date(b.createdAt)-new Date(a.createdAt)),
    keys: keys.map(item => ({ id: item.id, label: item.label, agentId: agentByUuid.get(item.agent_id)?.public_id || item.agent_id, suffix: item.suffix, status: item.status, createdAt: item.created_at })).sort((a,b) => new Date(b.createdAt)-new Date(a.createdAt)),
  };
}

export async function runConsoleAction(organizationId, action, payload) {
  return assertResult(await supabase.rpc('console_sandbox_action', { p_organization_id: organizationId, p_action: action, p_payload: payload }));
}
