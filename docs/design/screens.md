# Foxtation Mac app — design boards (text dump)

Source: `docs/design/mac-app.html` (bundled page; serve it with `python3 -m http.server` in this folder and open it in a browser — each board is a 1280×820 iframe). Bracketed values like `[RENEWAL DATE]` are placeholders in the design.

## Home
Sidebar: Foxtation · Home · Insights · Dictionary · Snippets · Style · footer card "Cloud cleanups today 186 of 500 · resets 07:00" (progress bar) · Settings · Help.
Top bar: "● Cloud cleanup on · MacBook Pro Microphone", avatar initials "KM".
"Good evening, Khairul" · "Hold [fn] anywhere to dictate. Release to paste." · Start dictation button.
Stat cards: Words today 1,284 · Avg. speed 142 wpm · Time saved 24 min · Streak 6 days.
TODAY list (View all): time · app (colored dot) · final text. e.g. 18:42 Slack "Oke, aku cek dulu deploy-nya ya…".

## Insights
Range: 7 days / 30 days / All time.
Speaking speed 142 wpm — bars You 142 vs Typing 40 — "3.5× faster than typing".
Fixes by Foxtation Cloud 1,032 — Filler words removed 412 · Punctuation & casing 388 · Self-corrections 232.
Words dictated 18,420 · Typing time saved 6h 08m · Dictations 1,146 · Mixed ID–EN 41%.
By app (7 apps used): Slack 38% · Cursor 24% · Mail 18% · WhatsApp 12% · Other 8%.
Streak card: 6-day streak, Longest · 14 days, contribution heatmap (Mon/Wed/Fri rows, Jun–Oct columns, Less→More legend).

## Dictionary
Header + "Add word". "Foxtation spells it your way. Add names, product terms and slang once. Every dictation and cloud cleanup uses this list, so “Jakmall” never turns into “jack mall”."
Suggested from your history: + Polar · + Cloudflare · + Durable Object · + khaisa.studio
Filter tabs: All 7 · Words 5 · Replacements 2
Rows: Khairul Muhtadin (Name) · Jakmall (Company) · Foxtation (Product) · n8n (Tool) · Khaisa Studio (Company) · gimana → bagaimana (Replace · Email only) · btw → by the way (Replace · All apps)

## Snippets
Header + "New snippet". "Say a cue. Drop the whole text. Save anything you type often — an address, a standup template, a prompt. Speak its cue mid-sentence and Foxtation pastes it in."
Two example cards: “alamat kantor” → [YOUR OFFICE ADDRESS]; “standup” → Kemarin: … Hari ini: … Blocker: …
Table CUE / EXPANDS TO / USED: my email 48× · standup 31× · polish prompt 22× · alamat kantor 9× · my calendar 4×

## Style
"Choose how cleanup sounds in each kind of app. Foxtation detects the app you’re typing in."
Group tabs: Chat · Work chat · Email · Code & terminal · Notes & docs
Style cards with example: Santai "Lowercase is fine, no trailing period, slang stays." (oke gw otw ya, 10 menit lagi sampe) · Netral "Normal casing and punctuation, words untouched." (Oke, gw otw ya. 10 menit lagi sampe.) · Rapi "Full sentences, standard spelling, no slang." (Oke, saya sedang di jalan. Sekitar 10 menit lagi sampai.)
APPS USING CHAT STYLE: WhatsApp × · Telegram × · Messages × · Discord × · + Add app
Toggles: Keep emoji I say out loud (“emoji ketawa” becomes 😂) · Split long messages (Break a long dictation into a few short chat bubbles)

## Settings (shared layout: left list SETTINGS General · Cloud cleanup · Shortcuts · Sounds; ACCOUNT License · Data & Privacy; footer "Foxtation v[VERSION]", "Cloud" badge)
### General
Push-to-talk: Hold [fn] and speak. Release to paste. (Change) · Hands-free mode: Double-tap fn to keep recording until you tap again. · Microphone: MacBook Pro Microphone (recommended) (Change) · Dictation languages: Indonesian · English — mixed speech stays mixed (Change) · App language: English / Bahasa Indonesia · Launch at login.
### License
Foxtation Cloud — Active — "Subscription via Polar · renews [RENEWAL DATE]" — Manage subscription.
License key (masked) — Show · Copy · Use another key.
This Mac · MacBook Pro — "Activated 12 Oct 2026 · 1 of [LIMIT] activations used" — Deactivate.
Cloud cleanups today 186 / 500 · resets 07:00 — "Past the limit, dictation keeps working and pastes the raw transcript."
### Data & Privacy
"Your voice never leaves this Mac. Only the text transcript is sent to Foxtation Cloud for cleanup, and it isn’t stored after the reply."
Cloud cleanup (Off: paste the raw on-device transcript, nothing sent.) · Share the app name (Sends “Slack” or “Mail” so cleanup can match the style.) · Keep history on this Mac (30 days / 7 days / Forever / Don’t keep) · Keep audio recordings (Lets you replay a dictation. Uses disk space.) · "1,146 dictations · 212 MB on disk" · Export history · Delete all history.

## Recording pill — states
"Floats above the Dock while you hold the key. One line, never covers what you’re typing."
1 · Listening — 0:07 timer + live level meter. Esc or × cancels.
2 · Cleaning up — "Cleaning up for Slack". Foxtation Cloud polishes the text for the app in front.
3 · Pasted — "Pasted · 24 words · Undo". Fades after 2 seconds. Undo swaps in the raw transcript.
4 · Fallback — "Daily limit reached · raw text pasted". On limit, license or network errors, dictation still works without cleanup.
