-- SECRET SANTA — Supabase database setup
-- Run this whole file once in Supabase Dashboard → SQL Editor.
-- Frontend uses only RPC functions; direct table access is revoked.

create extension if not exists pgcrypto;

create table if not exists public.ss_groups (
  code text primary key check (code ~ '^[A-F0-9]{10}$'),
  title text not null check (char_length(title) between 1 and 60),
  organizer_id uuid not null,
  drawn boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.ss_participants (
  group_code text not null references public.ss_groups(code) on delete cascade,
  user_id uuid not null,
  name text not null check (char_length(name) between 1 and 50),
  joined_at timestamptz not null default now(),
  primary key (group_code, user_id)
);

create table if not exists public.ss_assignments (
  group_code text not null references public.ss_groups(code) on delete cascade,
  giver_id uuid not null,
  receiver_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (group_code, giver_id),
  unique (group_code, receiver_id),
  check (giver_id <> receiver_id)
);

alter table public.ss_groups enable row level security;
alter table public.ss_participants enable row level security;
alter table public.ss_assignments enable row level security;
revoke all on table public.ss_groups, public.ss_participants, public.ss_assignments from anon, authenticated;
grant usage on schema public to anon, authenticated;

-- Create a new game and register its organizer as the first participant.
create or replace function public.ss_create_group(p_title text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_title text := left(trim(regexp_replace(coalesce(p_title, ''), '\s+', ' ', 'g')), 60);
  v_name text := left(trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 50);
begin
  if v_uid is null then raise exception 'Մուտքի սխալ։ Թարմացրու էջը և կրկին փորձիր։'; end if;
  if v_title = '' or v_name = '' then raise exception 'Լրացրու խաղի անունը և քո անունը։'; end if;

  loop
    v_code := upper(encode(gen_random_bytes(5), 'hex'));
    exit when not exists (select 1 from public.ss_groups where code = v_code);
  end loop;

  insert into public.ss_groups(code, title, organizer_id) values (v_code, v_title, v_uid);
  insert into public.ss_participants(group_code, user_id, name) values (v_code, v_uid, v_name);
  return jsonb_build_object('code', v_code, 'title', v_title, 'name', v_name, 'is_organizer', true);
end;
$$;

-- Join an existing game. The same browser identity cannot be added twice.
create or replace function public.ss_join_group(p_code text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_name text := left(trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')), 50);
  v_group public.ss_groups%rowtype;
begin
  if v_uid is null then raise exception 'Մուտքի սխալ։'; end if;
  if v_name = '' or v_code = '' then raise exception 'Գրիր անունդ և հրավերի կոդը։'; end if;

  select * into v_group from public.ss_groups where code = v_code for update;
  if not found then raise exception 'Խաղը չի գտնվել։ Ստուգիր հրավերի կոդը։'; end if;
  if v_group.drawn then raise exception 'Վիճակահանությունն արդեն սկսվել է․ նոր մասնակիցներ այլևս չեն կարող միանալ։'; end if;

  insert into public.ss_participants(group_code, user_id, name)
  values (v_code, v_uid, v_name)
  on conflict (group_code, user_id) do update set name = excluded.name;

  return jsonb_build_object('code', v_code, 'title', v_group.title, 'name', v_name, 'is_organizer', (v_group.organizer_id = v_uid));
end;
$$;

-- Return the room state only to people who are already participants.
create or replace function public.ss_dashboard(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_group public.ss_groups%rowtype;
  v_people jsonb;
begin
  if v_uid is null then raise exception 'Մուտքի սխալ։'; end if;
  select * into v_group from public.ss_groups where code = upper(trim(coalesce(p_code, '')));
  if not found then raise exception 'Խաղը չի գտնվել։'; end if;
  if not exists (select 1 from public.ss_participants where group_code = v_group.code and user_id = v_uid) then
    raise exception 'Դու այս խաղի մասնակից չես։ Մուտք գործիր հրավերի հղումով։';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('name', name) order by joined_at), '[]'::jsonb)
    into v_people
    from public.ss_participants where group_code = v_group.code;

  return jsonb_build_object(
    'title', v_group.title,
    'drawn', v_group.drawn,
    'is_organizer', (v_group.organizer_id = v_uid),
    'participants', v_people
  );
end;
$$;

-- Organizer-only draw. A random circular permutation guarantees nobody gets themselves.
create or replace function public.ss_start_draw(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_group public.ss_groups%rowtype;
  v_count integer;
  v_ids uuid[];
  i integer;
  j integer;
begin
  if v_uid is null then raise exception 'Մուտքի սխալ։'; end if;
  select * into v_group from public.ss_groups where code = v_code for update;
  if not found then raise exception 'Խաղը չի գտնվել։'; end if;
  if v_group.organizer_id <> v_uid then raise exception 'Միայն կազմակերպիչը կարող է սկսել վիճակահանությունը։'; end if;
  if v_group.drawn then raise exception 'Վիճակահանությունն արդեն կատարվել է։'; end if;

  select count(*) into v_count from public.ss_participants where group_code = v_code;
  if v_count < 2 then raise exception 'Պետք է առնվազն 2 մասնակից։'; end if;

  select array_agg(user_id order by random()) into v_ids
    from public.ss_participants where group_code = v_code;
  for i in 1..array_length(v_ids, 1) loop
    j := case when i = array_length(v_ids, 1) then 1 else i + 1 end;
    insert into public.ss_assignments(group_code, giver_id, receiver_id)
    values (v_code, v_ids[i], v_ids[j]);
  end loop;

  update public.ss_groups set drawn = true where code = v_code;
  return jsonb_build_object('ok', true, 'participant_count', v_count);
end;
$$;

-- Each participant can retrieve only their own assigned recipient.
create or replace function public.ss_reveal(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_name text;
begin
  if v_uid is null then raise exception 'Մուտքի սխալ։'; end if;
  if not exists (select 1 from public.ss_groups where code = v_code and drawn = true) then
    raise exception 'Վիճակահանությունը դեռ չի կատարվել։';
  end if;
  select p.name into v_name
    from public.ss_assignments a
    join public.ss_participants p on p.group_code = a.group_code and p.user_id = a.receiver_id
    where a.group_code = v_code and a.giver_id = v_uid;
  if v_name is null then raise exception 'Քո նշանակումը չի գտնվել։ Բացիր այն նույն սարքով և դիտարկիչով, որով միացել էիր։'; end if;
  return jsonb_build_object('name', v_name);
end;
$$;

-- RPC only: users cannot read/write the underlying tables directly.
revoke all on function public.ss_create_group(text, text) from public, anon;
revoke all on function public.ss_join_group(text, text) from public, anon;
revoke all on function public.ss_dashboard(text) from public, anon;
revoke all on function public.ss_start_draw(text) from public, anon;
revoke all on function public.ss_reveal(text) from public, anon;
grant execute on function public.ss_create_group(text, text) to authenticated;
grant execute on function public.ss_join_group(text, text) to authenticated;
grant execute on function public.ss_dashboard(text) to authenticated;
grant execute on function public.ss_start_draw(text) to authenticated;
grant execute on function public.ss_reveal(text) to authenticated;
