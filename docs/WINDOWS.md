# Running it on Windows

You need **one** thing installed: Node.js. The database is a free cloud account
you sign up for in about two minutes. Nothing else.

---

## 1. Install Node.js

Download the **LTS** build from [nodejs.org](https://nodejs.org) and run the
installer, accepting the defaults.

Then open **PowerShell** — press the Windows key, type `powershell`, press
Enter — and check it worked:

```powershell
node --version
```

You should see `v20` or higher. If the command is not recognised, close
PowerShell and open it again; the installer adds Node to your PATH and open
windows do not pick that up.

## 2. Get the code

```powershell
cd $HOME\Documents
git clone https://github.com/SEROUZCOIN/TelegramChatBot
cd TelegramChatBot
```

No Git? Either install it from [git-scm.com](https://git-scm.com), or download
the repository as a ZIP from GitHub and extract it.

## 3. Get a free database

The app stores everything in Postgres. Rather than installing it, use a free
hosted one:

1. Open **[neon.tech](https://neon.tech)** and sign up — no card required
2. Create a project, any name
3. Copy the **connection string**. It looks like this:

```
postgresql://user:password@ep-something.aws.neon.tech/neondb?sslmode=require
```

Supabase, Railway or any other Postgres host works identically.

## 4. Start it

```powershell
node run.js
```

The first run takes a few minutes — it downloads packages, sets up the database
and builds everything. It will **ask you to paste the database URL** from step 3
and remembers it, so you only do that once.

When it finishes:

```
Running

  Admin panel   http://localhost:3001
  API           http://localhost:3000/api

  Sign in as    admin@example.com / ChangeMe123!
```

Open **http://localhost:3001** in your browser and sign in.

## 5. Everyday commands

```powershell
node run.js              # start
node run.js --status     # what is running
node run.js --logs       # watch the API log
node run.js --stop       # stop
```

---

## The app on your phone

```powershell
pnpm --filter @tsp/mobile start
```

Install **Expo Go** from the App Store or Play Store, then scan the QR code that
appears. Your phone and your PC must be on the same wifi.

---

## If something goes wrong

**"running scripts is disabled on this system"**

Windows blocks scripts by default, which stops `pnpm` from running. Open
PowerShell **as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Answer `Y`, then try again in a normal PowerShell window.

**"pnpm is not recognised"**

pnpm comes with Node through a tool called corepack, which `run.js` enables for
you. If it could not, run this once in an Administrator PowerShell:

```powershell
corepack enable
```

**A Windows Firewall box appears on first run**

Node is opening ports 3000 and 3001 on your own machine. Allow it on private
networks. Nothing is exposed to the internet.

**"Could not connect with that URL"**

Copy the connection string again, whole. Neon's must end with
`?sslmode=require` — losing that tail is the usual cause.

**"port already in use"**

Something is still running from last time:

```powershell
node run.js --stop
```

**Anything else**

```powershell
node run.js --logs
```

The last error is normally the real one, and the lines above it say what the
launcher was doing at the time.
