export const STORAGE_KEY = 'fiducaro-console-sandbox-v1';

const policy = (daily, transaction, approval, vendors, assets = ['USDC'], privacy = 'Selective disclosure') => ({
  dailyLimit: daily,
  transactionLimit: transaction,
  approvalAbove: approval,
  vendors,
  assets,
  privacy,
  geography: 'US, EU',
});

export const initialData = {
  organization: { name: 'Acme Corp', treasury: 2840000, reserve: 500000, mode: 'sandbox' },
  agents: [
    { id: 'agt_82FD91', name: 'Procurement-07', purpose: 'Vendor procurement', status: 'Active', balance: 18420, spent30d: 12840, policyId: 'pol_procurement_v3', policy: policy(5000, 1000, 750, ['AWS', 'Anthropic', 'OpenAI'], ['USDC', 'ETH'], 'Enhanced') },
    { id: 'agt_4BC210', name: 'Research-04', purpose: 'Datasets and research', status: 'Active', balance: 12450, spent30d: 3680, policyId: 'pol_research_v2', policy: policy(3000, 500, 400, ['OpenAI', 'Anthropic', 'AWS', 'DataHub']) },
    { id: 'agt_93CE12', name: 'Compute-02', purpose: 'Compute resources', status: 'Active', balance: 36000, spent30d: 27200, policyId: 'pol_compute_v1', policy: policy(12000, 4000, 2500, ['AWS', 'NVIDIA Cloud', 'Google Cloud'], ['USDC', 'ETH']) },
    { id: 'agt_129AA0', name: 'Operations-03', purpose: 'Software subscriptions', status: 'Active', balance: 7850, spent30d: 1950, policyId: 'pol_operations_v1', policy: policy(1500, 500, 300, ['OpenAI', 'Google Cloud', 'Anthropic']) },
    { id: 'agt_7A1C09', name: 'Logistics-01', purpose: 'Shipping operations', status: 'Suspended', balance: 9500, spent30d: 2100, policyId: 'pol_logistics_v1', policy: policy(2500, 800, 600, ['DHL', 'FedEx']) },
  ],
  approvals: [
    { id: 'apr_1001', agentId: 'agt_82FD91', vendor: 'AWS', amount: 880, asset: 'USDC', reason: 'Inference services', status: 'Pending', createdAt: new Date().toISOString() },
    { id: 'apr_1002', agentId: 'agt_93CE12', vendor: 'NVIDIA Cloud', amount: 3000, asset: 'USDC', reason: 'GPU compute', status: 'Pending', createdAt: new Date().toISOString() },
  ],
  payments: [
    { id: 'pay_8999', agentId: 'agt_82FD91', vendor: 'AWS', amount: 880, asset: 'USDC', status: 'Review', approvalId: 'apr_1001', createdAt: new Date().toISOString() },
    { id: 'pay_9000', agentId: 'agt_93CE12', vendor: 'NVIDIA Cloud', amount: 3000, asset: 'USDC', status: 'Review', approvalId: 'apr_1002', createdAt: new Date().toISOString() },
    { id: 'pay_9001', agentId: 'agt_4BC210', vendor: 'DataHub', amount: 240, asset: 'USDC', status: 'Completed', createdAt: new Date().toISOString() },
    { id: 'pay_9002', agentId: 'agt_82FD91', vendor: 'OpenAI', amount: 145, asset: 'USDC', status: 'Completed', createdAt: new Date().toISOString() },
    { id: 'pay_9003', agentId: 'agt_93CE12', vendor: 'AWS', amount: 1950, asset: 'USDC', status: 'Completed', createdAt: new Date().toISOString() },
  ],
  events: [
    { id: 'evt_1', at: new Date().toISOString(), actor: 'POLICY', action: 'human_review.required', subject: 'Compute-02', detail: '$3,000 USDC · NVIDIA Cloud', tone: 'amber' },
    { id: 'evt_2', at: new Date().toISOString(), actor: 'POLICY', action: 'human_review.required', subject: 'Procurement-07', detail: '$880 USDC · AWS', tone: 'amber' },
    { id: 'evt_3', at: new Date().toISOString(), actor: 'AGENT', action: 'payment.completed', subject: 'Research-04', detail: '$240 USDC · DataHub', tone: 'green' },
    { id: 'evt_4', at: new Date().toISOString(), actor: 'AGENT', action: 'payment.completed', subject: 'Procurement-07', detail: '$145 USDC · OpenAI', tone: 'green' },
  ],
  keys: [
    { id: 'key_7c21', label: 'Procurement sandbox', agentId: 'agt_82FD91', suffix: '•••• 7C21', status: 'Active', createdAt: new Date().toISOString() },
  ],
  webhooks: [],
};

export function loadDemo() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (saved?.organization && Array.isArray(saved.agents)) return saved;
  } catch { /* fall back to seeded sandbox */ }
  return initialData;
}

export const money = (value, digits = 0) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: digits, maximumFractionDigits: digits }).format(value);
export const shortDate = value => new Date(value).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
export const makeId = prefix => `${prefix}_${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
export const event = (actor, action, subject, detail, tone = 'cyan') => ({ id: makeId('evt'), at: new Date().toISOString(), actor, action, subject, detail, tone });
export const agentName = (data, id) => data.agents.find(agent => agent.id === id)?.name || id;

export function evaluateSandboxPayment({ agent, amount, vendor, asset, spentToday = 0 }) {
  if (!agent || !Number.isFinite(amount) || amount <= 0 || !vendor?.trim()) return { outcome: 'blocked', reason: 'Invalid payment request' };
  if (agent.status !== 'Active') return { outcome: 'blocked', reason: 'Agent account is suspended' };
  if (!agent.policy.assets.includes(asset)) return { outcome: 'blocked', reason: 'Asset is not allowed' };
  if (!agent.policy.vendors.some(value => value.toLowerCase() === vendor.trim().toLowerCase())) return { outcome: 'blocked', reason: 'Counterparty is not approved' };
  if (amount > agent.balance) return { outcome: 'blocked', reason: 'Insufficient agent balance' };
  if (amount > agent.policy.transactionLimit) return { outcome: 'blocked', reason: 'Transaction limit exceeded' };
  if (spentToday + amount > agent.policy.dailyLimit) return { outcome: 'blocked', reason: 'Daily limit exceeded' };
  if (amount > agent.policy.approvalAbove) return { outcome: 'review', reason: 'Human approval required' };
  return { outcome: 'approved', reason: 'Policy passed' };
}
