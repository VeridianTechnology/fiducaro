# Fiducaro website and Console prototype

A React and Vite front end for Fiducaro. The public site is the marketing and documentation layer. The Console is a human control plane prototype; agents are intended to use a future API.

## Run

```bash
npm install
npm run dev
```

Open the URL printed by Vite, then select **Open Console**, or visit `/console/overview`. Run `npm test` for sandbox policy tests and `npm run build` for a production build.

## Public site

Home, Product, Developers, Security, Use Cases, and Company. The supplied logo and wallpaper are used as assets; page mockups guided real HTML and CSS layouts.

## Console prototype

The Console has Organization Overview, Agents, Accounts, Policies, Payments, Treasury, Approvals, Privacy, Activity, Developers, Security, and Organization views. Agent detail includes Overview, Balance, Permissions, Transactions, API, and Logs tabs.

Demo actions include creating and suspending agents, allocating test balances, editing policy, simulating payments, resolving approvals, changing privacy modes, generating nonfunctional credential previews, configuring nondelivering webhooks, and resetting sample data. Actions update the overview and activity stream. State is stored only in the current browser's `localStorage` under `fiducaro-console-sandbox-v1`.

**This is not a financial system.** There is no sign-in, server database, actual API, real credential, webhook delivery, wallet, settlement, or money movement. Sample organizations, balances, vendors, payments, policy outcomes, and metrics are fictional. The payment policy code is a local demonstration and must not be used as production financial authorization.

## Integration boundaries

Before live use, add human authentication and organization membership, database tables with organization-scoped access rules, server-side policy evaluation, immutable audit records, credential hashing and rotation, idempotency handling, reliable approval and payment state transitions, a ledger, webhook delivery, and independent security review. Never put a Supabase secret or service-role key in Vite client code.

Request Access and Contact on the public site currently use `hello@fiducaro.com` as a placeholder mail destination. Replace it in `src/App.jsx` with an approved contact channel before publishing.
