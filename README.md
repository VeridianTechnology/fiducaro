# Fiducaro website and Console prototype

A React and Vite front end for Fiducaro. The public site is the marketing and documentation layer. The Console is a human control plane prototype; agents are intended to use a future API.

## Run

```bash
npm install
npm run dev
```

Copy `.env.example` to `.env.local` and set the Supabase project URL and publishable key. The first four SQL migrations are applied to project `egffkcjplbryzowofjte`; the newest anonymous/confirmation guard migration is pending. Apply migrations in version order when setting up a new project. The publishable key may be used by Vite; never put a secret or service-role key there. Open the URL printed by Vite, then select **Open Console**, or visit `/console/overview`. Run `npm test` and `npm run build` to verify the project.

## Auth configuration

Enable new user email/password signup in the hosted Supabase Auth settings and keep email confirmation required. Disable anonymous, Web3, and Solana sign-ins for this email/password milestone. Add the app origin's `/console/overview` and `/console/reset-password` URLs to Auth's allowed redirect URLs. Add both local development and production origins when applicable. Registration and recovery links use the current browser origin; the code does not hardcode a deployment hostname. New confirmed users create a sandbox organization through `create_demo_organization`, which makes them its owner. The newest SQL file blocks anonymous or unconfirmed accounts from Console membership and onboarding; apply it before opening public registration.

## Public site

Home, Product, Developers, Security, Use Cases, and Company. The supplied logo and wallpaper are used as assets; page mockups guided real HTML and CSS layouts.

## Console prototype

The Console has Organization Overview, Agents, Accounts, Policies, Payments, Treasury, Approvals, Privacy, Activity, Developers, Security, and Organization views. Agent detail includes Overview, Balance, Permissions, Transactions, API, and Logs tabs.

Human operators sign in through Supabase Auth. After sign-in, the first user creates a sandbox organization and becomes its owner. Organization records and simulated actions persist in Postgres. Row Level Security limits reads to members, and guarded database functions perform sandbox mutations. Demo actions include creating and suspending agents, allocating test balances, editing policy, simulating payments, resolving approvals, changing privacy modes, generating nonfunctional credential previews, configuring nondelivering webhooks, and resetting sample data.

**This is not a financial system.** There is no agent API, real credential, webhook delivery, wallet, settlement, or money movement. Sample organizations, balances, vendors, payments, policy outcomes, and metrics are fictional. The SQL policy simulation is for a sandbox only and must not be used as production financial authorization.

## Integration boundaries

Before live use, add immutable audit records, real machine credential issuance and rotation, idempotency handling, reliable approval and payment state transitions, a double-entry ledger, webhook delivery, MFA, and independent security review. AI agents should use a separate Fiducaro API and never authenticate as human Supabase users.

Request Access and Contact on the public site currently use `hello@fiducaro.com` as a placeholder mail destination. Replace it in `src/App.jsx` with an approved contact channel before publishing.
