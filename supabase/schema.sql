-- LocalStock Concierge shared database schema.
-- Run this in your Supabase SQL Editor or apply it as a migration after linking a project.
-- All app tables are RLS-protected and scoped through household membership.

create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.localstock_households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  invite_code text unique not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.localstock_household_members (
  household_id uuid not null references public.localstock_households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table if not exists public.localstock_products (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.localstock_households(id) on delete cascade,
  name text not null,
  normalized_name text not null,
  category text not null,
  location_name text not null,
  unit text not null,
  management_type text not null,
  min_stock numeric not null default 0,
  ideal_stock numeric not null default 0,
  cycle_days integer,
  lead_days integer,
  barcode text,
  aliases text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, normalized_name)
);

create table if not exists public.localstock_inventory_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.localstock_households(id) on delete cascade,
  product_id uuid not null references public.localstock_products(id) on delete cascade,
  type text not null,
  quantity numeric not null,
  source text not null,
  note text,
  confidence numeric not null default 1 check (confidence >= 0 and confidence <= 1),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.localstock_shopping_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.localstock_households(id) on delete cascade,
  product_id uuid references public.localstock_products(id) on delete set null,
  name text not null,
  quantity numeric,
  unit text,
  store_type text not null default 'any',
  priority text not null default 'medium',
  reason text not null,
  status text not null default 'active',
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.localstock_wish_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.localstock_households(id) on delete cascade,
  name text not null,
  url text,
  price integer,
  priority text not null default 'medium',
  status text not null default 'active',
  memo text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.localstock_receipts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.localstock_households(id) on delete cascade,
  raw_text text not null,
  store_name text,
  purchased_at timestamptz,
  total_amount integer,
  parsed_json jsonb,
  image_local_path text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

drop function if exists public.localstock_is_household_member(uuid);

create or replace function private.localstock_is_household_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.localstock_household_members m
    where m.household_id = target_household
      and m.user_id = (select auth.uid())
  );
$$;

create or replace function private.localstock_is_household_owner(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.localstock_household_members m
    where m.household_id = target_household
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
  );
$$;

create or replace function private.localstock_household_created_by(target_household uuid, target_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.localstock_households h
    where h.id = target_household
      and h.created_by = target_user
  );
$$;

create or replace function public.localstock_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function private.localstock_join_household(invite_code_input text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_household uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  select h.id
    into target_household
  from public.localstock_households h
  where h.invite_code = upper(trim(invite_code_input))
  limit 1;

  if target_household is null then
    raise exception 'invite code not found';
  end if;

  insert into public.localstock_household_members (household_id, user_id, role)
  values (target_household, (select auth.uid()), 'member')
  on conflict (household_id, user_id) do nothing;

  return target_household;
end;
$$;

create or replace function public.localstock_join_household(invite_code_input text)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.localstock_join_household(invite_code_input);
$$;

grant usage on schema private to authenticated;
grant execute on function private.localstock_is_household_member(uuid) to authenticated;
grant execute on function private.localstock_is_household_owner(uuid) to authenticated;
grant execute on function private.localstock_household_created_by(uuid, uuid) to authenticated;
grant execute on function private.localstock_join_household(text) to authenticated;
revoke execute on function public.localstock_join_household(text) from public;
revoke execute on function public.localstock_join_household(text) from anon;
grant execute on function public.localstock_join_household(text) to authenticated;

grant usage on schema public to authenticated;
grant select, insert, update on table public.localstock_households to authenticated;
grant select, insert on table public.localstock_household_members to authenticated;
grant select, insert, update on table public.localstock_products to authenticated;
grant select, insert, update on table public.localstock_inventory_events to authenticated;
grant select, insert, update on table public.localstock_shopping_items to authenticated;
grant select, insert, update on table public.localstock_wish_items to authenticated;
grant select, insert, update on table public.localstock_receipts to authenticated;

drop trigger if exists localstock_households_touch_updated_at on public.localstock_households;
create trigger localstock_households_touch_updated_at
before update on public.localstock_households
for each row execute function public.localstock_touch_updated_at();

drop trigger if exists localstock_products_touch_updated_at on public.localstock_products;
create trigger localstock_products_touch_updated_at
before update on public.localstock_products
for each row execute function public.localstock_touch_updated_at();

drop trigger if exists localstock_wish_items_touch_updated_at on public.localstock_wish_items;
create trigger localstock_wish_items_touch_updated_at
before update on public.localstock_wish_items
for each row execute function public.localstock_touch_updated_at();

alter table public.localstock_households enable row level security;
alter table public.localstock_household_members enable row level security;
alter table public.localstock_products enable row level security;
alter table public.localstock_inventory_events enable row level security;
alter table public.localstock_shopping_items enable row level security;
alter table public.localstock_wish_items enable row level security;
alter table public.localstock_receipts enable row level security;

drop policy if exists "localstock households visible to members" on public.localstock_households;
create policy "localstock households visible to members"
on public.localstock_households
for select to authenticated
using ((select private.localstock_is_household_member(id)));

drop policy if exists "localstock households can be created by signed in users" on public.localstock_households;
create policy "localstock households can be created by signed in users"
on public.localstock_households
for insert to authenticated
with check (created_by = (select auth.uid()));

drop policy if exists "localstock household owners can update household" on public.localstock_households;
create policy "localstock household owners can update household"
on public.localstock_households
for update to authenticated
using (
  (select private.localstock_is_household_owner(id))
)
with check ((select private.localstock_is_household_owner(id)));

drop policy if exists "localstock members visible to same household" on public.localstock_household_members;
create policy "localstock members visible to same household"
on public.localstock_household_members
for select to authenticated
using ((select private.localstock_is_household_member(household_id)));

drop policy if exists "localstock user can add self to created household" on public.localstock_household_members;
drop policy if exists "localstock owner can invite members" on public.localstock_household_members;
drop policy if exists "localstock members can be inserted when allowed" on public.localstock_household_members;
create policy "localstock members can be inserted when allowed"
on public.localstock_household_members
for insert to authenticated
with check (
  (
    user_id = (select auth.uid())
    and (select private.localstock_household_created_by(household_id, (select auth.uid())))
  )
  or (select private.localstock_is_household_owner(household_id))
);

drop policy if exists "localstock products are household scoped" on public.localstock_products;
drop policy if exists "localstock products can be inserted by members" on public.localstock_products;
drop policy if exists "localstock products can be updated by members" on public.localstock_products;
create policy "localstock products are household scoped"
on public.localstock_products
for select to authenticated
using ((select private.localstock_is_household_member(household_id)));

create policy "localstock products can be inserted by members"
on public.localstock_products
for insert to authenticated
with check ((select private.localstock_is_household_member(household_id)));

create policy "localstock products can be updated by members"
on public.localstock_products
for update to authenticated
using ((select private.localstock_is_household_member(household_id)))
with check ((select private.localstock_is_household_member(household_id)));

drop policy if exists "localstock events are household scoped" on public.localstock_inventory_events;
drop policy if exists "localstock events can be inserted by members" on public.localstock_inventory_events;
drop policy if exists "localstock events can be updated by members" on public.localstock_inventory_events;
create policy "localstock events are household scoped"
on public.localstock_inventory_events
for select to authenticated
using ((select private.localstock_is_household_member(household_id)));

create policy "localstock events can be inserted by members"
on public.localstock_inventory_events
for insert to authenticated
with check (
  (select private.localstock_is_household_member(household_id))
  and created_by = (select auth.uid())
);

create policy "localstock events can be updated by members"
on public.localstock_inventory_events
for update to authenticated
using ((select private.localstock_is_household_member(household_id)))
with check ((select private.localstock_is_household_member(household_id)));

drop policy if exists "localstock shopping items are household scoped" on public.localstock_shopping_items;
drop policy if exists "localstock shopping items can be inserted by members" on public.localstock_shopping_items;
drop policy if exists "localstock shopping items can be updated by members" on public.localstock_shopping_items;
create policy "localstock shopping items are household scoped"
on public.localstock_shopping_items
for select to authenticated
using ((select private.localstock_is_household_member(household_id)));

create policy "localstock shopping items can be inserted by members"
on public.localstock_shopping_items
for insert to authenticated
with check (
  (select private.localstock_is_household_member(household_id))
  and created_by = (select auth.uid())
);

create policy "localstock shopping items can be updated by members"
on public.localstock_shopping_items
for update to authenticated
using ((select private.localstock_is_household_member(household_id)))
with check ((select private.localstock_is_household_member(household_id)));

drop policy if exists "localstock wish items are household scoped" on public.localstock_wish_items;
drop policy if exists "localstock wish items can be inserted by members" on public.localstock_wish_items;
drop policy if exists "localstock wish items can be updated by members" on public.localstock_wish_items;
create policy "localstock wish items are household scoped"
on public.localstock_wish_items
for select to authenticated
using ((select private.localstock_is_household_member(household_id)));

create policy "localstock wish items can be inserted by members"
on public.localstock_wish_items
for insert to authenticated
with check (
  (select private.localstock_is_household_member(household_id))
  and created_by = (select auth.uid())
);

create policy "localstock wish items can be updated by members"
on public.localstock_wish_items
for update to authenticated
using ((select private.localstock_is_household_member(household_id)))
with check ((select private.localstock_is_household_member(household_id)));

drop policy if exists "localstock receipts are household scoped" on public.localstock_receipts;
drop policy if exists "localstock receipts can be inserted by members" on public.localstock_receipts;
drop policy if exists "localstock receipts can be updated by members" on public.localstock_receipts;
create policy "localstock receipts are household scoped"
on public.localstock_receipts
for select to authenticated
using ((select private.localstock_is_household_member(household_id)));

create policy "localstock receipts can be inserted by members"
on public.localstock_receipts
for insert to authenticated
with check (
  (select private.localstock_is_household_member(household_id))
  and created_by = (select auth.uid())
);

create policy "localstock receipts can be updated by members"
on public.localstock_receipts
for update to authenticated
using ((select private.localstock_is_household_member(household_id)))
with check ((select private.localstock_is_household_member(household_id)));

create index if not exists localstock_products_household_idx on public.localstock_products (household_id, is_active, normalized_name);
create index if not exists localstock_households_created_by_idx on public.localstock_households (created_by);
create index if not exists localstock_household_members_user_idx on public.localstock_household_members (user_id);
create index if not exists localstock_events_household_product_idx on public.localstock_inventory_events (household_id, product_id, created_at desc);
create index if not exists localstock_events_product_idx on public.localstock_inventory_events (product_id);
create index if not exists localstock_events_created_by_idx on public.localstock_inventory_events (created_by);
create index if not exists localstock_shopping_household_status_idx on public.localstock_shopping_items (household_id, status, created_at desc);
create index if not exists localstock_shopping_product_idx on public.localstock_shopping_items (product_id);
create index if not exists localstock_shopping_created_by_idx on public.localstock_shopping_items (created_by);
create index if not exists localstock_wish_household_status_idx on public.localstock_wish_items (household_id, status, created_at desc);
create index if not exists localstock_wish_created_by_idx on public.localstock_wish_items (created_by);
create index if not exists localstock_receipts_household_created_idx on public.localstock_receipts (household_id, created_at desc);
create index if not exists localstock_receipts_created_by_idx on public.localstock_receipts (created_by);
