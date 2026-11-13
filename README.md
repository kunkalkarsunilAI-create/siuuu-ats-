# Meridian ATS

A lightweight applicant tracking system for an IT services company that hires against client projects. It is a single self-contained page (`index.html`), with no build step.

## Features

- **Job requisitions**: client, project, billing rate, skills, experience band, CTC range, location, openings, target closure date, recruiter and hiring manager
- **Candidates**: contact details, current and expected CTC, notice period, experience, skills, source (Naukri, LinkedIn, employee referral, named consultancy, direct), resume link and DPDP consent
- **Applications**: one candidate can apply to several jobs
- **Pipeline**: Applied → Screened → Internal Interview → Client Round → Offered → BGV → Joined, plus Rejected and Dropped Out at any point. Every move is time-stamped and records who made it
- **Duplicate detection**: warns when a phone number or email already exists, and shows which job and recruiter already have the candidate
- **Notes**: per candidate, with author and time
- **Interviews**: round, time, panel, mode, outcome and feedback
- **Offers and BGV**: offered CTC and joining date. BGV must be marked Clear before a candidate can be marked Joined
- **Flags**: notice period vs. the job's target date, and an offer drop-out risk score
- **Dashboard**: hires vs. quarterly target, open positions, offer → join rate, time to fill, drop-out and rejection reasons, results by source including consultancy fees, and recruiter workload
- **Client status update**: generates a ready-to-paste summary for each job
- **DPDP**: consent capture, erasure per candidate, and bulk erasure of candidates inactive past a retention period

## Storage and sign-in

The page picks its storage when it starts:

- **Hosted anywhere else, e.g. Vercel**: it uses the Supabase project `meridian-ats`. Users sign in with **Clerk** (application "Meridian ATS", development instance `picked-cattle-8969.clerk.accounts.dev`). Supabase trusts Clerk session tokens through its Third-Party Auth integration, and the session token must carry `role` and `email` claims. If `CLERK_PK` in `index.html` is empty, the app falls back to Supabase's own email and password login. Only emails listed in `team_members` can create an account. Roles:
  - `admin`: full access, plus managing the team list in Settings
  - `recruiter`: can add and edit records
  - `viewer`: read-only, for hiring managers

  Changes from colleagues appear live through Supabase Realtime. Every insert, update and delete is written to `audit_log` (no personal data is kept there).
- **Hosted as a Claude artifact**: it uses the artifact runtime's shared `db` capability.

The database schema, access rules (row level security) and triggers are in `supabase/migrations/`. The Supabase URL and publishable key in `index.html` are safe to expose: all access is enforced by row level security.

### Supabase settings to check

In the Supabase dashboard, open Authentication → URL Configuration and set **Site URL** to the deployed address, e.g. `https://siuuu-ats.vercel.app`. Confirmation and password-reset emails link back to that address.

## Data model

| Collection | Key fields |
|---|---|
| `jobs` | title, client, project, type, skills[], expMin/expMax, ctcMin/ctcMax (₹ lakh), location, openings, targetDate, billingRate, recruiter, hiringManager, status |
| `candidates` | name, phone, email, currentCompany, currentCtc, expectedCtc, noticeDays, totalExp, skills[], source, sourceDetail, consent, notes[] |
| `applications` | candidateId, jobId, stage, history[], interviews[], offer, bgv, rejectReason / dropReason |
| `config/main` | team, managers, consultancies, commission, quarterTarget, retentionMonths |
