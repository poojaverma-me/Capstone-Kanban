# Team Board (Kanban + Supabase)

A single-page Kanban board in an Apple-style design. Tasks can have **any number of assignees**, and data lives in **Supabase**, so the whole team shares one live board.

```
kanban-supabase/
├── index.html        the board (HTML + CSS + JS, no build step)
├── agent.html        the Board Agent page: operating manual + tools for an AI agent
├── schema.sql        tables, policies and live updates for Supabase
├── agent-setup.sql   run log, restricted agent role and the agent token
├── manifest.webmanifest, sw.js   installable app (PWA) + offline app shell
├── favicon.ico
└── icons/            app icons, Apple touch icon, favicons
```

## Set up (about 5 minutes)

1. Create a free project at [supabase.com](https://supabase.com).
2. In the dashboard, open **SQL Editor → New query**, paste all of `schema.sql`, and click **Run**. This creates three tables (`members`, `tasks`, `task_assignees`), adds five starter teammates, and turns on live updates.
3. Open `index.html`. It's already set up for the team project (`ccbaaipwfqihuemeiwxr`), so it connects on its own.

Teammates just open the same `index.html`; there's nothing to paste. Changes show up on everyone's screen within a second.

To point the page at a different project, change `DEFAULT_CONFIG` near the top of the script in `index.html`, or use ⚙ → Disconnect and paste a new Project URL and publishable key.

There's also **Try without Supabase**, which runs the same board with sample data saved only in your browser.

## Using it

- **Add a task:** "+ Add a task" at the bottom of a column (Enter to save), the column's **+**, the **New task** button, or press `N`.
- **Assign people:** open a task and tap as many teammates as you like.
- **Move tasks:** drag cards between and within columns. On a phone, change Status inside the task. With the keyboard, use `⌥←` / `⌥→` on a focused card.
- **Filter:** tap teammates' avatars in the top bar to show only their tasks. `/` jumps to search.
- **Team:** add, rename, recolour or remove people. Removing someone unassigns them; their tasks stay.
- **Rename the board:** click its name in the top bar.

## Board Agent (`agent.html`)

A page for an AI agent that controls a browser. You give it a document, email, meeting notes or a request. It works out the tasks and who owns each one, checks for duplicates, writes and runs the SQL, verifies the result and reports back. It asks you only when something essential is missing or ambiguous.

- **Setup (once):** run `agent-setup.sql` in the Supabase SQL Editor. The last result is the **agent token**; copy it, because it's shown only once.
- **Use:** open `agent.html` (or click **Agent** on the board), paste the token into panel 1, paste the material into panel 2, and tell your agent: *"Process the input on the Board Agent page."*
- **What the agent sees:**
  - the full operating manual: workflow, owner rules, field rules, duplicates, clarification, SQL templates, verification, safety, report format and an example
  - live schema, members, tasks and recent runs
  - a SQL console
  - a run log
  - `window.boardAgent` for agents that can run JavaScript
- **Safety:**
  - The agent's SQL runs as a restricted `board_agent` role. It can read and write `members`, `tasks`, `task_assignees` and `agent_runs`, but can't create, change or drop tables, or see the token store.
  - Every run is saved in `agent_runs` with the input and the statements it executed.
  - To revoke access: `delete from public.agent_tokens;`. To make a new token: `select public.agent_new_token('label');`.

## How the data is modelled

| Table | Purpose |
|---|---|
| `members` | Teammates (`name`, `color`) |
| `tasks` | Cards (`title`, `description`, `status` = `todo` / `in_progress` / `done`, `priority`, `due_date`, `position`) |
| `task_assignees` | Join table: one row per (task, member) pair, which is what allows one-to-many assignment |

Deleting a task or a member cascades to `task_assignees`.

## Security note

`schema.sql` lets anyone who has your Project URL and publishable key read and edit the board. That's convenient for a class team and fine for project tasks, but:

- don't put private or sensitive information on the board;
- never use the **service_role / secret** key in the page (the app refuses it).

To lock it down later, enable Supabase Auth and change the policies from `to anon, authenticated` to `to authenticated`.

## Install it as an app (PWA)

When the board is served over **https** (GitHub Pages, Netlify, Vercel), it can be installed like a native app with its own icon and window:

- **Mac / Windows (Chrome, Edge):** click **Install** in the board's top bar, or the install icon in the address bar.
- **iPhone / iPad (Safari):** Share → **Add to Home Screen**.
- **Android (Chrome):** menu → **Install app**.

Right-click the app icon (or long-press it on a phone) for shortcuts: **New task** and **Board Agent**. The app shell opens even offline; tasks need a connection, because they live in Supabase.

Opening `index.html` straight from your computer still works, but it can't be installed that way. Browsers only allow installing from https.

## Hosting (optional)

To give the team a link, put the folder on any static host. With GitHub Pages: repo **Settings → Pages → Deploy from branch → `main` / root**. The board will be at `https://<user>.github.io/<repo>/`.
