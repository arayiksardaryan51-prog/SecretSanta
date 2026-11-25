# Secret Santa — Online multi-device edition (GitHub Pages + Supabase)

This project has separate pages and supports multiple independent game rooms:

- `index.html` — create a room or join one with an invitation code.
- `game.html?code=...` — the individual room for that game.
- `assets/config.js` — public Supabase connection settings.
- `assets/style.css` — shared design.
- `supabase/schema.sql` — database tables and secure server-side RPC functions.

**Important:** GitHub Pages only serves the website files. Supabase is the shared online database/auth service that keeps rooms and participant names available across different devices. Without completing the Supabase setup below, game data cannot be shared between devices.

## A. Configure Supabase (required, one time)

1. Create a project at https://supabase.com/.
2. In the Supabase dashboard, open **SQL Editor → New query**.
3. Open `supabase/schema.sql`, copy the entire file into the SQL editor, and click **Run**. Wait for the success message.
4. Open **Authentication → Sign In / Providers** and enable **Anonymous Sign-Ins**. The exact label may vary slightly in the dashboard.
5. Open **Project Settings → API** (or API Keys). Copy the **Project URL** and the **anon/public** or **publishable** key.
6. Open `assets/config.js` and replace the two placeholder values, keeping the quotation marks:

```js
export const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
export const SUPABASE_ANON_KEY = "YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY";
```

Never put a `service_role` key or any secret key in a website file. The public key is intended for browser use; the SQL functions enforce access.

## B. Publish on GitHub Pages

1. Create a GitHub repository.
2. Upload the **contents** of this project folder to the repository root (not an extra nested folder). The root must contain `index.html`, `game.html`, `assets/`, `supabase/`, and `README.md`.
3. In the repository, open **Settings → Pages**.
4. Under Build and deployment, choose **Deploy from a branch**, branch `main`, folder `/(root)`, then Save.
5. Wait for GitHub Pages to publish the website. Open the published site over `https://`.

## C. How to play

1. Open the published website and create a game. The creator is automatically registered as the organizer and first participant.
2. The site redirects to that game's own room page and displays both a shareable invitation link and a 10-character code.
3. Send the invitation link or code to friends. They open the link, enter their name, and join the same room from their own devices.
4. The participant list refreshes every four seconds. The organizer can also see the participant count.
5. Once everyone has joined, the organizer starts the draw. It can happen only once.
6. Each participant opens the same room on the same browser/device used to join and presses **Բացահայտել իմ Secret Santa-ին**. Only their own assigned recipient is returned.

Each new room receives its own unique code. Creating another game does not overwrite an existing room.

## D. Important notes

- Anonymous sign-in identity is stored in the browser. The organizer and each participant must use the same browser/device they used when creating/joining. Clearing site data, using private/incognito mode, or switching browsers can create a different identity.
- The `anon`/publishable key is public by design. Do not expose the Supabase `service_role` or secret key.
- The draw uses a random circular permutation, so each participant gets exactly one recipient and nobody gets themselves. The assignment is kept server-side; the room page never downloads everyone else's assignments.
- If you change the SQL after the first setup, rerun the full SQL script in the same Supabase project. This script uses `create table if not exists` and `create or replace function` for repeat setup.

## E. Quick troubleshooting

- **“Կայքը դեռ միացված չէ տվյալների բազային”** — the URL/key placeholders in `assets/config.js` were not replaced.
- **Anonymous sign-in disabled** — enable Anonymous Sign-Ins in Supabase Authentication providers.
- **Function does not exist / schema cache error** — run all of `supabase/schema.sql` in Supabase SQL Editor.
- **Invalid API key** — copy the correct anon/public or publishable key from the same Supabase project as the Project URL.
- **Friends cannot see the room/participants** — make sure everyone uses the same published site URL, and that Supabase setup is complete. Share the invitation link generated inside the room, not the organizer's browser address unless it includes `game.html?code=...`.
- **“Դու այս խաղի մասնակից չես”** — open the invite link and join with your name first. Then return to the room using the same browser.

## Verification boundary

The HTML/JavaScript and SQL files are included in this ZIP. The local project can be syntax-checked, but a real cross-device test requires your own Supabase project credentials and a published GitHub Pages URL. Those private project-specific settings are intentionally not guessed or embedded here.
