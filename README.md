# Track Transit

**Fleet management for taxi park owners and drivers in Mukono, Uganda.**

A full-stack web app for real-time vehicle tracking, driver management, trip logging, fault reporting, and mobile money subscription billing. Click any section below to expand it.

---

<details>
<summary><strong>Table of Contents</strong></summary>
<br>

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Database Schema](#3-database-schema)
4. [Feature Reference](#4-feature-reference)
5. [Tech Stack](#5-tech-stack)
6. [File Structure](#6-file-structure)
7. [Deployment Guide](#7-deployment-guide)
8. [Environment Variables](#8-environment-variables)
9. [Database Setup](#9-database-setup)
10. [Payment Integration Setup](#10-payment-integration-setup)
11. [Security Model](#11-security-model)
12. [Design System](#12-design-system)

</details>

---

<details>
<summary><strong>1. Project Overview</strong></summary>
<br>

Track Transit solves a real coordination problem at Mukono taxi park: owners have no reliable way to know where their taxis are, how many trips they have completed, or whether a breakdown has occurred — unless a driver calls them. This system replaces that phone-tag workflow with a live dashboard and a structured driver reporting interface.

**Core workflows:**

- An owner logs in with email and password, sees a live map of their fleet, and can tap any taxi to see its current driver, conductor, trip count, and any open maintenance issues.
- A driver logs in with a username, password, and a one-time PIN that the owner sees on their screen — this confirms the owner approves the driver accessing their fleet data.
- Once inside, the driver selects their taxi, enters their conductor's name, and starts sharing GPS. Every trip is logged with one tap. Faults are reported through a categorised form that immediately appears in the owner's maintenance panel.
- Billing is automated: the first taxi and first two drivers are free. Additional resources are charged at UGX 15,000 per taxi and UGX 10,000 per driver per month, collected through MTN Mobile Money or Airtel Money.

</details>

---

<details>
<summary><strong>2. Architecture</strong></summary>
<br>

```
┌─────────────────────────────────────────────────────────┐
│                      Browser (Client)                    │
│                                                         │
│   React 18 (CDN, no build step)                        │
│   ├── Owner Dashboard (desktop-first, sidebar nav)      │
│   └── Driver Interface  (mobile-first, single column)   │
│                                                         │
│   Leaflet.js + OpenStreetMap tiles  (live map)          │
│   Agrandir (headings) + Open Sauce One (body) fonts     │
└──────────────┬──────────────────────────┬───────────────┘
               │  Supabase JS client       │  fetch() calls
               ▼                           ▼
┌──────────────────────────┐   ┌───────────────────────────┐
│   Supabase (Backend)     │   │  Supabase Edge Functions   │
│                          │   │  (Deno runtime)            │
│  PostgreSQL database     │   │                            │
│  ├── owners              │   │  initiate-payment          │
│  ├── taxis               │   │  └── calls Flutterwave API │
│  ├── drivers             │   │      saves pending payment │
│  ├── otp_requests        │   │                            │
│  ├── maintenance         │   │  verify-payment            │
│  ├── location_updates    │   │  └── polls Flutterwave API │
│  ├── trips               │   │      updates payment row   │
│  └── payments            │   │                            │
│                          │   └───────────┬───────────────┘
│  Supabase Auth           │               │
│  └── owner accounts      │               ▼
│      (email + password)  │   ┌───────────────────────────┐
│                          │   │  Flutterwave              │
│  Row Level Security      │   │  ├── MTN Mobile Money UG  │
│  └── per-owner isolation │   │  └── Airtel Money UG      │
│                          │   └───────────────────────────┘
│  PostgreSQL functions    │
│  ├── generate_otp()      │
│  ├── check_driver_pwd()  │
│  ├── hash_password()     │
│  └── reset_daily_trips() │
└──────────────────────────┘

Hosting: Netlify (static, no server, free tier)
```

**Key architectural decisions:**

- **No build step.** The entire frontend is a single `index.html` file loading React, Babel, Leaflet, and Supabase from CDN. This keeps deployment to a simple drag-and-drop and eliminates Node.js tooling from the hosting environment.
- **Supabase as the only backend.** PostgreSQL handles all data. Row Level Security enforces that each owner can only see and modify their own fleet data, without any application-layer access control code.
- **Drivers are not Supabase Auth users.** Drivers are stored in a plain `drivers` table with bcrypt-hashed passwords, authenticated entirely through a custom login flow and OTP challenge. This avoids the complexity of managing Supabase Auth users for potentially hundreds of drivers across many owners.
- **Edge Functions for payment secrets.** Flutterwave's secret API key never touches the browser. All payment initiation and verification goes through Supabase Edge Functions running in a Deno environment on Supabase's servers.
- **15-second polling for live data.** The owner dashboard refreshes taxis, metrics, and pending OTPs every 15 seconds using `setInterval`. This is simpler and more reliable than WebSocket subscriptions for this context, while still providing near-real-time awareness.

</details>

---

<details>
<summary><strong>3. Database Schema</strong></summary>
<br>

### `owners`
Stores profile data for fleet owners. The `id` column is a foreign key to `auth.users`, meaning owners authenticate through Supabase Auth.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK, FK → auth.users) | Supabase Auth user ID |
| `name` | TEXT | Owner's full name |
| `fleet_name` | TEXT | Business or fleet name |
| `phone` | TEXT | Contact phone number |
| `created_at` | TIMESTAMPTZ | Row creation timestamp |

### `taxis`
One row per taxi in a fleet. Updated by both the owner (CRUD) and the driver (GPS, trips, status).

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Taxi identifier |
| `owner_id` | UUID (FK → owners) | Fleet the taxi belongs to |
| `plate` | TEXT UNIQUE | Number plate (e.g. UAX 123B) |
| `route` | TEXT | Assigned route |
| `driver` | TEXT | Name of current driver (set by driver at shift start) |
| `conductor` | TEXT | Name of current conductor |
| `status` | TEXT | active / inactive / maintenance / breakdown |
| `trips_today` | INT | Trip count for the current day |
| `lat` / `lng` | DOUBLE PRECISION | Last known GPS coordinates |
| `last_seen` | TIMESTAMPTZ | Time of last GPS update |
| `created_at` | TIMESTAMPTZ | Row creation timestamp |

### `drivers`
Driver accounts managed by the owner from the dashboard. Passwords are stored as bcrypt hashes; the raw password is never saved.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Driver identifier |
| `owner_id` | UUID (FK → owners) | Fleet this driver belongs to |
| `username` | TEXT UNIQUE | Login username |
| `password_hash` | TEXT | bcrypt hash (pgcrypto) |
| `name` | TEXT | Driver's full name |
| `phone` | TEXT | Contact phone number |
| `active` | BOOLEAN | Whether the driver can log in |
| `created_at` | TIMESTAMPTZ | Row creation timestamp |

### `otp_requests`
Short-lived one-time codes generated when a driver logs in.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | OTP record identifier |
| `owner_id` | UUID (FK → owners) | Which owner sees this OTP |
| `driver_id` | UUID (FK → drivers) | Which driver requested it |
| `otp` | TEXT | 4-digit code |
| `used` | BOOLEAN | Whether the code has been consumed |
| `expires_at` | TIMESTAMPTZ | Expiry (default 15 minutes after creation) |
| `created_at` | TIMESTAMPTZ | Row creation timestamp |

### `maintenance`
Fault and breakdown reports submitted by drivers.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Report identifier |
| `taxi_id` | UUID (FK → taxis) | Which taxi the fault was reported on |
| `driver_id` | UUID (FK → drivers) | Who reported it |
| `type` | TEXT | Category (Engine Warning, Brakes, Breakdown, etc.) |
| `note` | TEXT | Driver's description of the issue |
| `resolved` | BOOLEAN | Whether the owner has marked it resolved |
| `resolved_at` | TIMESTAMPTZ | When it was resolved |
| `reported_at` | TIMESTAMPTZ | When it was submitted |

### `location_updates`
Append-only GPS history. Every position fix creates one row here, and also updates the taxi's `lat`/`lng`/`last_seen`.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Update identifier |
| `taxi_id` | UUID (FK → taxis) | Which taxi this position belongs to |
| `driver_id` | UUID (FK → drivers) | Which driver was driving |
| `lat` / `lng` | DOUBLE PRECISION | GPS coordinates |
| `accuracy` | REAL | GPS accuracy in metres |
| `created_at` | TIMESTAMPTZ | Timestamp of the fix |

### `trips`
One row per completed trip, inserted when the driver taps Log Trip.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Trip identifier |
| `taxi_id` | UUID (FK → taxis) | Which taxi completed the trip |
| `driver_id` | UUID (FK → drivers) | Driver on this trip |
| `conductor` | TEXT | Conductor on this trip |
| `trip_date` | DATE | Date of the trip (defaults to current date) |
| `logged_at` | TIMESTAMPTZ | Exact time the trip was logged |

### `payments`
Payment records created by the `initiate-payment` Edge Function and updated by `verify-payment`.

| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Payment record identifier |
| `owner_id` | UUID (FK → owners) | Which owner made the payment |
| `tx_ref` | TEXT UNIQUE | Unique Flutterwave transaction reference |
| `amount` | INTEGER | Amount in UGX |
| `currency` | TEXT | Always UGX |
| `provider` | TEXT | MTN or AIRTEL |
| `phone` | TEXT | Mobile money number used |
| `status` | TEXT | pending / successful / failed |
| `description` | TEXT | Human-readable label |
| `flw_ref` | TEXT | Flutterwave's internal reference |
| `created_at` | TIMESTAMPTZ | When payment was initiated |
| `updated_at` | TIMESTAMPTZ | When status last changed |

### Database Functions

| Function | Purpose |
|---|---|
| `generate_otp(driver_id, owner_id)` | Invalidates old OTPs for a driver and inserts a new 4-digit code. Called during driver login. |
| `check_driver_password(driver_id, password)` | Compares a plain-text password against the stored bcrypt hash using pgcrypto. Returns boolean. |
| `hash_password(password)` | Hashes a plain-text password with bcrypt (blowfish). Called when the owner creates or updates a driver. |
| `reset_daily_trips()` | Sets `trips_today` to zero on all taxis. Intended to be scheduled as a cron job at midnight. |

</details>

---

<details>
<summary><strong>4. Feature Reference</strong></summary>
<br>

<details>
<summary>4.1 Authentication</summary>
<br>

**Owner Login**
Owners authenticate through Supabase Auth (email + password). On successful login, the app fetches the owner's name and fleet name from the `owners` table and stores them in React state for the session. Supabase persists the session in `localStorage`, so refreshing the page keeps the owner logged in.

**Invite Flow**
New owners are created via Supabase Dashboard → Authentication → Users → Invite user. Supabase sends an invite email with a link back to the app containing an access token in the URL hash. The app detects this token on load, shows a "Set Up Your Account" screen, and prompts the owner to enter their name, fleet name, and password. The password is set via `supabase.auth.updateUser()` and the owner profile row is upserted into the `owners` table.

**Driver Login**
Drivers do not use Supabase Auth. Their login is a two-step process:

1. **Credentials check:** The driver enters their username and password. The app looks up the driver row by username, then calls the `check_driver_password` RPC to verify the password server-side without ever transmitting the hash to the client.
2. **OTP verification:** If credentials are correct, `generate_otp` is called on the server, creating a 4-digit code in the `otp_requests` table. The owner sees this code in real time on their Pending OTPs screen. The driver reads the code from the owner and enters it. The app validates it against the database (checking it is unused and not expired) and marks it as used before granting access.

This design ensures a driver cannot access a fleet without the owner being physically present and aware.

</details>

<details>
<summary>4.2 Owner Dashboard</summary>
<br>

The owner dashboard is a sidebar-navigation interface with six sections. The sidebar collapses into a slide-out drawer on screens narrower than 768px, toggled by a hamburger button in the top bar. All data refreshes automatically every 15 seconds.

**Live Map**
A full-width interactive map rendered with Leaflet.js on OpenStreetMap tiles (no API key required). Each taxi is shown as a circular marker colour-coded by status — green for active, red for breakdown, orange for maintenance or inactive. Tapping a marker opens a popup showing the taxi's plate, route, current driver, conductor, trips today, open maintenance issues, and last GPS update time.

**My Taxis**
A searchable table of every taxi in the fleet. Owners can add, edit, and delete taxis. If the free tier limit is reached and no active payment exists for the month, an inline billing gate appears and the Add button redirects to the Billing page.

**Drivers**
A searchable table of all drivers. Owners can add drivers (password is bcrypt-hashed server-side before storage), edit details and reset passwords, deactivate a driver without deleting their history, or delete a driver permanently. The same billing gate applies for exceeding the free driver limit.

**Maintenance**
A table of all fault reports across the fleet showing taxi, fault category, description, report time, and status. Owners can mark any open issue as resolved.

**Pending OTPs**
A table that auto-refreshes every 15 seconds showing any active OTP codes. Each row shows the driver's name, username, their 4-digit code displayed prominently, and the expiry time. This is the screen the owner shows to the driver during the second login step.

**Billing**
Described in section 4.4 below.

</details>

<details>
<summary>4.3 Driver Interface</summary>
<br>

The driver interface is a single-column, mobile-optimised layout with no sidebar. All functionality is presented as stacked cards.

**Shift Setup**
The driver selects their taxi from a dropdown and enters the conductor's name. Saving writes the driver's name and conductor to the taxi row and sets its status to `active`.

**Trip Counter**
Shows trips completed today, loaded from the database on login. Each tap of Log Trip inserts a row into `trips` and increments `trips_today` on the taxi. The count persists across refreshes and re-logins.

**GPS Tracking**
Calls `navigator.geolocation.watchPosition()` with `enableHighAccuracy: true`. On each position fix, the taxi's `lat`, `lng`, and `last_seen` are updated in the database, and a row is inserted into `location_updates` for history. The owner's map picks up changes on the next 15-second refresh.

**Fault Reporting**
A grid of eight fault categories (Engine Warning, Tyre Issue, Brakes, Breakdown, Accident, Fuel Issue, Electrical, Other) plus a free-text description field. Submitting inserts a row into `maintenance` linked to the driver's taxi and appears immediately in the owner's Maintenance tab.

</details>

<details>
<summary>4.4 Billing & Payments</summary>
<br>

**Subscription Model**

| Resource | Included free | Additional cost |
|---|---|---|
| Taxis | 1 | UGX 15,000 per extra taxi per month |
| Drivers | 2 | UGX 10,000 per extra driver per month |

The monthly bill is calculated at runtime from the current taxi and driver counts. Example: 4 taxis + 5 drivers = (3 × 15,000) + (3 × 10,000) = **UGX 75,000/month**.

**Payment Flow**
1. Owner selects MTN MoMo or Airtel Money, enters their number, clicks Pay
2. The `initiate-payment` Edge Function calls Flutterwave with the secret key and Flutterwave sends a USSD prompt to the owner's phone
3. The browser polls `verify-payment` every 5 seconds while the owner approves on their phone
4. On confirmation, the `payments` row is updated to `successful` and the subscription is active for the month

**Billing Gate**
If an owner tries to add a taxi or driver beyond the free limits without an active payment this calendar month, the Add button redirects to Billing and a warning appears above the table.

</details>

</details>

---

<details>
<summary><strong>5. Tech Stack</strong></summary>
<br>

| Layer | Technology | Why |
|---|---|---|
| Hosting | Netlify Free | Global CDN, instant deploys, free SSL |
| Frontend framework | React 18 (via CDN) | Component model without a build pipeline |
| Transpilation | Babel Standalone (CDN) | JSX in the browser without a build step |
| Database | Supabase PostgreSQL | Managed Postgres with auth, RLS, and a free tier |
| Authentication | Supabase Auth | Email/password auth with invite-by-email flow |
| Backend functions | Supabase Edge Functions (Deno) | Serverless TypeScript for payment API calls |
| Maps | Leaflet.js 1.9 | Open-source, zero API key required |
| Map tiles | OpenStreetMap | Free, community-maintained, covers Uganda well |
| Payment gateway | Flutterwave | Supports MTN MoMo and Airtel Money Uganda |
| Heading font | Agrandir (Fontshare) | Free, distinctive grotesque |
| Body font | Open Sauce One (Google Fonts) | Legible at small sizes on mobile screens |
| Password hashing | pgcrypto (blowfish) | Server-side bcrypt via PostgreSQL extension |

</details>

---

<details>
<summary><strong>6. File Structure</strong></summary>
<br>

```
track-transit/
│
├── index.html                  # Entire frontend — HTML, CSS, and React JSX
│
├── background.png              # Background image for splash/login screens
├── logo.png                    # App logo shown in splash and sidebar
│
├── supabase-schema.sql         # All CREATE TABLE, RLS, and function definitions
├── netlify.toml                # Netlify deployment configuration
│
├── PAYMENTS.md                 # Step-by-step Flutterwave integration guide
├── README.md                   # This file
│
└── supabase/
    └── functions/
        ├── initiate-payment/
        │   └── index.ts        # Edge Function: calls Flutterwave charge endpoint
        └── verify-payment/
            └── index.ts        # Edge Function: polls Flutterwave for payment status
```

</details>

---

<details>
<summary><strong>7. Deployment Guide</strong></summary>
<br>

### Prerequisites
- A free [Supabase](https://supabase.com) account
- A free [Netlify](https://netlify.com) account
- A free [Flutterwave](https://flutterwave.com) account (for payments)
- The [Supabase CLI](https://supabase.com/docs/guides/cli) installed (for Edge Functions)

### Step 1 — Supabase Project
1. Go to [supabase.com](https://supabase.com) and create a new project
2. Choose the `eu-west-1` region (closest to Uganda)
3. From **Settings → API**, note your Project URL, anon/public key, and service_role key

### Step 2 — Database Setup
1. In Supabase Dashboard → **SQL Editor**, paste the full contents of `supabase-schema.sql` and click Run
2. Go to **Database → Replication** and enable Realtime for `taxis`, `otp_requests`, and `maintenance`

### Step 3 — Configure the App
Open `index.html` and replace the placeholder values near the top of the `<script>` block:

```js
const SUPABASE_URL = 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = 'your-anon-key';
const FLW_PUBLIC_KEY = 'FLWPUBK_your-public-key';
```

### Step 4 — Deploy Edge Functions
```bash
npm install -g supabase
supabase login
supabase link --project-ref YOUR_PROJECT_REF

supabase secrets set FLW_SECRET_KEY=FLWSECK_your-secret-key
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

supabase functions deploy initiate-payment
supabase functions deploy verify-payment
```

### Step 5 — Deploy to Netlify

**Option A — Drag and drop:**
1. Go to [app.netlify.com](https://app.netlify.com) → Add new site → Deploy manually
2. Drag the entire `track-transit/` folder into the browser

**Option B — Git:**
1. Push the project to a GitHub or GitLab repository
2. In Netlify: Add new site → Import an existing project → connect the repo
3. Build command: *(leave blank)*, Publish directory: `.`

### Step 6 — Configure Supabase Redirect URLs
1. Supabase Dashboard → **Authentication → URL Configuration**
2. Set **Site URL** to your Netlify URL (e.g. `https://track-transit.netlify.app`)
3. Under **Redirect URLs**, add `https://your-site.netlify.app` and `https://your-site.netlify.app/**`

### Step 7 — Create the First Owner Account
1. Supabase Dashboard → **Authentication → Users → Invite user**
2. Enter the owner's email and click Send
3. The owner clicks the email link, which opens the Set Up Your Account screen on your live site

</details>

---

<details>
<summary><strong>8. Environment Variables</strong></summary>
<br>

All client-side configuration is done by editing `index.html` directly. Edge Function secrets are set via the Supabase CLI and never leave the server.

| Variable | Where set | Description |
|---|---|---|
| `SUPABASE_URL` | `index.html` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | `index.html` | Supabase anon/public key (safe to expose) |
| `FLW_PUBLIC_KEY` | `index.html` | Flutterwave public key (safe to expose) |
| `FLW_SECRET_KEY` | Supabase secret | Flutterwave secret key (never in the browser) |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase secret | Service role key for Edge Functions to bypass RLS |

</details>

---

<details>
<summary><strong>9. Database Setup</strong></summary>
<br>

Run `supabase-schema.sql` in full in the Supabase SQL Editor. It is safe to run multiple times (`CREATE TABLE IF NOT EXISTS` and `CREATE OR REPLACE FUNCTION` throughout).

**Daily trip reset:** The `reset_daily_trips()` function sets `trips_today` to zero on all taxis. To run it automatically at midnight, enable the `pg_cron` extension and schedule it:

```sql
-- Enable in Supabase Dashboard → Database → Extensions first
SELECT cron.schedule(
  'reset-daily-trips',
  '0 0 * * *',
  $$ SELECT reset_daily_trips(); $$
);
```

</details>

---

<details>
<summary><strong>10. Payment Integration Setup</strong></summary>
<br>

See `PAYMENTS.md` for the complete step-by-step guide. In summary:

1. Sign up at [dashboard.flutterwave.com](https://dashboard.flutterwave.com) and complete KYC verification
2. Note your public and secret keys from **Settings → API Keys**
3. Test in sandbox mode using Flutterwave's test credentials:
   - MTN: `256780000001` — PIN: `1234`
   - Airtel: `256750000001` — PIN: `1234`
4. Deploy the Edge Functions with your secret key set as a Supabase secret
5. Switch to live mode when ready for real transactions

</details>

---

<details>
<summary><strong>11. Security Model</strong></summary>
<br>

**Row Level Security**
Every table has RLS enabled. Owners can only read and write rows where `owner_id = auth.uid()`. The `payments` table is read-only for authenticated users; only the service role (used by Edge Functions) can insert or update payment records.

**Driver Authentication**
Drivers are not Supabase Auth users. They authenticate against the `drivers` table using a custom RPC that runs bcrypt comparison inside PostgreSQL via pgcrypto. The `password_hash` column is explicitly revoked from the `anon` and `authenticated` roles so it can never be returned by a SELECT query from the browser.

**OTP Security**
OTP codes expire 15 minutes after creation. Each code is single-use — marked `used = true` when consumed. When a new OTP is generated for a driver, any previous unused codes for that driver are automatically invalidated by the `generate_otp` function.

**Payment Security**
Flutterwave's secret API key is stored only as a Supabase Edge Function secret, never in `index.html` or any client-accessible location. The Edge Functions verify the caller's Supabase Auth JWT before making any Flutterwave API calls, and verify that the `owner_id` in the request matches the authenticated user.

**HTTPS**
Netlify provides free TLS certificates for all sites. All Supabase communication is encrypted in transit.

</details>

---

<details>
<summary><strong>12. Design System</strong></summary>
<br>

### Colours

| Role | Value | Usage |
|---|---|---|
| Primary | `#1565C0` | Buttons, active sidebar item, map header, stat values |
| Primary dark | `#0D47A1` | Hover states, gradient |
| Primary pale | `#E3F2FD` | Badge backgrounds, focus rings |
| Secondary | `#2E7D32` | Active status, resolved badges, GPS active state |
| Secondary pale | `#E8F5E9` | Badge backgrounds |
| Accent | `#E65100` | Fault reporting, billing highlights, OTP badge |
| Accent pale | `#FFF3E0` | Badge backgrounds, billing gate |

### Typography

| Role | Font | Weights |
|---|---|---|
| Headings, stat values, logo | Agrandir | 400, 700, 800, 900 |
| Body text, labels, inputs, buttons | Open Sauce One | 300, 400, 500, 600 |

### Spacing & Radii

| Token | Value | Used for |
|---|---|---|
| `--radius` | 12px | Cards, modals |
| `--radius-sm` | 8px | Inputs, buttons, badges |
| `--radius-lg` | 16px | Role cards, login card, plan cards |

### Icons
All icons are inline SVGs from [Lucide](https://lucide.dev) using `stroke="currentColor"` so they inherit text colour automatically in all states.

### Responsive Breakpoint
The single breakpoint is `768px`. Below this the sidebar collapses and is replaced by a hamburger menu. The driver interface has no sidebar and is mobile-first by default.

</details>
