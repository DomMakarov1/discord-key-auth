# Discord Key Auth Starter

Discord.js bot + Express API + Prisma (SQLite) for script key auth.

## Features

- `/register user pass` creates account
- `/issue days` (admin only) generates a `Member` key
- `/key code` redeems issued key for the caller's registered account
- `POST /auth/login` validates credentials + active Member license
- `POST /auth/validate` validates JWT token

## Setup

1. Copy `.env.example` to `.env` and fill values.
2. Install deps:
   - `npm install`
3. Generate Prisma client:
   - `npm run prisma:generate`
4. Create DB/migration:
   - `npm run prisma:migrate`
5. Run:
   - `npm start`

## Env

- `DISCORD_TOKEN` bot token
- `DISCORD_CLIENT_ID` app client id
- `DISCORD_GUILD_ID` test guild id
- `ADMIN_DISCORD_IDS` comma list of admin discord ids
- `JWT_SECRET` random long secret
- `API_PORT` api port
- `DATABASE_URL` sqlite url

## Lua Login Example

```lua
local HttpService = game:GetService("HttpService")

local function req()
    return request or (syn and syn.request) or http_request
end

local function login(apiBase, username, password)
    local r = req()
    if not r then return false, "No request() in executor" end
    local res = r({
        Url = apiBase .. "/auth/login",
        Method = "POST",
        Headers = {["Content-Type"] = "application/json"},
        Body = HttpService:JSONEncode({username = username, password = password})
    })
    if not res or res.StatusCode ~= 200 then
        return false, "Auth failed"
    end
    local data = HttpService:JSONDecode(res.Body)
    if not data.ok then return false, data.error or "Login failed" end
    return true, data.token
end
```

## Notes

- This is a starter. Add rate limiting, IP logging, and stronger anti-abuse before production.
- For production, use Postgres and HTTPS behind a reverse proxy.
