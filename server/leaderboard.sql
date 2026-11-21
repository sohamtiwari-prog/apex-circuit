-- Apex Circuit: the online leaderboard (Supabase).
--
-- Paste all of this into your Supabase project's SQL Editor and press Run,
-- once. It's safe to run again (it replaces the functions, keeps the laps).
--
-- What it makes:
--   laps       every lap anyone drives (time, sectors, car, track, weather,
--              assists, setup, app version, phone model) and, for each
--              player's best time-trial laps, the ghost (the car's path).
--              You see it all in Table Editor > laps; tick "hidden" on a
--              row to take a cheat off the leaderboards.
--   min_laps   the fastest lap that's physically possible on each track:
--              anything quicker is turned away.
-- The game can't read or change the table itself: it can only post laps
-- (submit_laps) and read the leaderboards (leaderboard, my_rank,
-- get_ghost) - which never show anyone's player id or phone.

create table if not exists public.laps (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  player_id     uuid not null,
  nickname      text not null,
  track         text not null,
  car           text not null,
  mode          text,
  ranked        boolean not null default false,   -- a clean time-trial lap: counts for the leaderboards
  lap_ms        integer not null,
  sectors       integer[],
  weather       text,
  assists       jsonb,
  setup         jsonb,
  ghost         text,                             -- base64 (scripts/ghost_share.gd pack)
  ghost_samples integer,
  app_version   text,
  platform      text,
  device        text,
  hidden        boolean not null default false    -- you: hide a lap from the leaderboards
);
create index if not exists laps_board on public.laps (track, car, lap_ms) where ranked and not hidden;
create index if not exists laps_player on public.laps (player_id);

create table if not exists public.min_laps (
  track  text primary key,
  min_ms integer not null
);
insert into public.min_laps (track, min_ms) values
  ('silvermoor', 46880), ('brianza', 46160), ('ardennes', 55680), ('riviera', 26400),
  ('styria', 34320), ('entrelagos', 34240), ('desert', 43120), ('ile_royale', 34800),
  ('pannonia', 34960), ('marina', 39440), ('gulf', 42240), ('lakeside', 42240),
  ('duinen', 34080), ('caspian', 47760), ('lone_star', 44080), ('red_sea', 49440),
  ('isebay', 46480), ('jiading', 43600), ('kestrel_park', 16480),
  ('pinecrest', 27435), ('harbourline', 36195), ('redrock', 29510),
  ('lago_brisa', 30000), ('porto_solmar', 30000)
on conflict (track) do update set min_ms = excluded.min_ms;

-- Nobody reaches the tables directly from the game: only through the
-- functions below.
alter table public.laps enable row level security;
alter table public.min_laps enable row level security;
revoke all on public.laps from anon, authenticated;
revoke all on public.min_laps from anon, authenticated;

-- Posts up to 50 laps at once. Laps that are impossible (faster than the
-- track allows, or a ghost that doesn't match the time) are dropped; the
-- rest are kept. Returns how many were kept.
create or replace function public.submit_laps(p_laps jsonb)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  m integer;
  ms integer;
  gs integer;
  n integer := 0;
begin
  if jsonb_typeof(p_laps) <> 'array' or jsonb_array_length(p_laps) > 50 then
    return 0;
  end if;
  for r in select value from jsonb_array_elements(p_laps) loop
    begin
      ms := (r->>'lap_ms')::integer;
      gs := nullif(r->>'ghost_samples', '')::integer;
      select min_ms into m from min_laps where track = r->>'track';
      if ms is null or ms < coalesce(m, 15000) or ms > 1800000 then
        continue;
      end if;
      if r ? 'ghost' and (gs is null or abs(gs * 100 - ms) > 1500 or length(r->>'ghost') > 200000) then
        r := r - 'ghost';
        gs := null;
      end if;
      insert into laps (player_id, nickname, track, car, mode, ranked, lap_ms, sectors,
                        weather, assists, setup, ghost, ghost_samples, app_version, platform, device)
      values (
        (r->>'player_id')::uuid,
        left(coalesce(nullif(trim(r->>'nickname'), ''), 'Driver'), 20),
        left(r->>'track', 40),
        left(r->>'car', 40),
        left(r->>'mode', 20),
        coalesce((r->>'ranked')::boolean, false),
        ms,
        (select array_agg(x::integer) from jsonb_array_elements_text(r->'sectors') x),
        left(r->>'weather', 20),
        r->'assists',
        r->'setup',
        r->>'ghost',
        gs,
        left(r->>'app_version', 20),
        left(r->>'platform', 20),
        left(r->>'device', 80));
      n := n + 1;
    exception when others then
      null;                       -- a malformed lap: skip it, keep the rest
    end;
  end loop;
  return n;
end $$;

-- The top of a leaderboard: each player's best clean time-trial lap with
-- this car on this track. ("mine" marks the asking player's own row.)
create or replace function public.leaderboard(p_track text, p_car text, p_me uuid default null, p_limit integer default 10)
returns table (lap_id bigint, nickname text, lap_ms integer, sectors integer[], weather text,
               set_at timestamptz, has_ghost boolean, mine boolean)
language sql stable security definer set search_path = public as $$
  select b.id, b.nickname, b.lap_ms, b.sectors, b.weather, b.created_at, b.ghost is not null, b.player_id = p_me
  from (
    select distinct on (player_id) *
    from laps
    where track = p_track and car = p_car and ranked and not hidden
    order by player_id, lap_ms, (ghost is null), id
  ) b
  order by b.lap_ms, b.id
  limit least(greatest(p_limit, 1), 50)
$$;

-- Where a player stands: their best, their position and how many have set a
-- time with this car on this track.
create or replace function public.my_rank(p_track text, p_car text, p_me uuid)
returns table (rank bigint, total bigint, best_ms integer)
language sql stable security definer set search_path = public as $$
  with b as (
    select player_id, min(lap_ms) as ms
    from laps
    where track = p_track and car = p_car and ranked and not hidden
    group by player_id
  )
  select (select count(*) from b where b.ms < me.ms) + 1, (select count(*) from b), me.ms
  from b as me
  where me.player_id = p_me
$$;

-- One lap's ghost, to race.
create or replace function public.get_ghost(p_lap bigint)
returns table (ghost text, nickname text, lap_ms integer, track text, car text)
language sql stable security definer set search_path = public as $$
  select ghost, nickname, lap_ms, track, car from laps where id = p_lap and not hidden and ghost is not null
$$;

revoke all on function public.submit_laps(jsonb) from public;
revoke all on function public.leaderboard(text, text, uuid, integer) from public;
revoke all on function public.my_rank(text, text, uuid) from public;
revoke all on function public.get_ghost(bigint) from public;
grant execute on function public.submit_laps(jsonb) to anon, authenticated;
grant execute on function public.leaderboard(text, text, uuid, integer) to anon, authenticated;
grant execute on function public.my_rank(text, text, uuid) to anon, authenticated;
grant execute on function public.get_ghost(bigint) to anon, authenticated;
