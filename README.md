# 🚕 Track Transit — Mukono Taxi Park Fleet Management

A fleet management web app for taxi park owners and drivers in Mukono, Uganda.

## Features
- **Owner Dashboard**: Live map (OpenStreetMap/Leaflet), fleet CRUD, maintenance tracking
- **Driver App**: GPS tracking, trip logging, fault reporting
- **OTP Auth**: Drivers need a one-time code sent to the owner's device
- **Free Stack**: Supabase (DB + Auth + Realtime) + Netlify (hosting) + OpenStreetMap (maps)

---

## 🚀 Deploy in 5 Steps

### 1. Create Supabase Project (free)
1. Go to [supabase.com](https://supabase.com) → New Project
2. Choose a region close to Uganda (e.g. `eu-west-1`)
3. Note your **Project URL** and **anon/public key** (Settings → API)

### 2. Set Up Database
1. Supabase Dashboard → SQL Editor
2. Paste the entire contents of `supabase-schema.sql` and run it
3. In Dashboard → Database → Replication, enable realtime on:
   - `location_updates`
   - `otp_requests`
   - `maintenance`

### 3. Configure the App
Open `index.html` and find these lines near the top of the `<script>` block:
```js
const SUPABASE_URL = window.SUPABASE_URL || 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || 'YOUR_SUPABASE_ANON_KEY';
```
Replace with your actual values, OR set them via environment variables (see below).

### 4. Deploy to Netlify (free)
**Option A — Drag & Drop:**
1. Go to [app.netlify.com](https://app.netlify.com) → New site → Deploy manually
2. Drag the project folder into the browser

**Option B — Git:**
1. Push this folder to a GitHub/GitLab repo
2. Netlify → New site from Git → connect repo
3. Build command: *(leave blank)*  
4. Publish directory: `.`

### 5. Create Owner Account
1. In Supabase Dashboard → Authentication → Users → Invite user
2. Or use your app's owner login to sign up with email/password
3. After signing up, run the sample data INSERT in `supabase-schema.sql` using your new UUID

---

## 📱 Using the App

### Owner
- Visit your Netlify URL → **Fleet Owner**
- Login with your email + password
- Map shows all taxis with color-coded status (🟢 active, 🔴 breakdown)
- Tap a taxi to see driver, conductor, trips, maintenance
- **My Taxis** tab → Add/Edit/Delete taxis
- **Maintenance** tab → Resolve reported faults

### Driver
- Visit Netlify URL → **Driver**
- Enter username + password → an OTP notification goes to the owner's device
- Owner reads the OTP and tells the driver (or shows their screen)
- Driver enters OTP → gets access to that owner's fleet
- Select which taxi they're driving + conductor name
- Tap **Start GPS Tracking** to share location
- Use **+ Log Trip** for each completed trip
- Report faults via the fault form (goes to owner's maintenance panel)

---

## 🛠️ Tech Stack (all free)

| Layer | Technology | Cost |
|-------|-----------|------|
| Hosting | Netlify Free | $0 |
| Database | Supabase Free tier (500MB) | $0 |
| Auth | Supabase Auth | $0 |
| Realtime | Supabase Realtime | $0 |
| Maps | Leaflet.js + OpenStreetMap | $0 |
| Frontend | React (CDN) | $0 |

---

## 📡 Making GPS Realtime Live

When Supabase is connected, the driver's GPS position is written to:
- `location_updates` table (history)
- `taxis` table (`lat`, `lng`, `last_seen`) — live update

The owner's map subscribes to Supabase Realtime on the `taxis` table and refreshes markers automatically.

Add this code to `DriverDashboard` to push GPS to Supabase:
```js
// Inside startTracking callback, after setLocation():
await supabase.from('location_updates').insert({
  taxi_id: selectedTaxi,
  driver_id: user.id,
  lat: pos.coords.latitude,
  lng: pos.coords.longitude,
  accuracy: pos.coords.accuracy
});
await supabase.from('taxis').update({
  lat: pos.coords.latitude,
  lng: pos.coords.longitude,
  last_seen: new Date().toISOString()
}).eq('id', selectedTaxi);
```

And in `OwnerMap`, subscribe to realtime:
```js
const channel = supabase.channel('taxi-locations')
  .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'taxis' }, 
    payload => updateMarker(payload.new))
  .subscribe();
```

---

## 📲 SMS OTP (Production)
For real SMS OTPs to the owner's phone, integrate **Africa's Talking** (Ugandan SMS gateway, has free sandbox):
1. Sign up at [africastalking.com](https://africastalking.com) — has Uganda coverage
2. Use their Node.js SDK in a Netlify Function (`/netlify/functions/send-otp.js`)
3. The function generates OTP, stores it in Supabase, and sends SMS to owner's number

---

## 🎨 Colors
- Primary: `#1565C0` (blue)
- Secondary: `#2E7D32` (green)  
- Accent: `#E65100` (orange)
