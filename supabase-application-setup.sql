-- Run this once in the Supabase SQL Editor before enabling public applications.
-- Applicants must be signed in; anonymous users can only read active programs.

grant usage on schema public to anon, authenticated;
grant select on public.programs to anon, authenticated;
grant insert, update on public.programs to authenticated;
grant select on public.admin_users to authenticated;
grant select on public.applications to authenticated;
revoke insert, update, delete on public.applications from anon, authenticated;

alter table public.applications
  add column if not exists applicant_user_id uuid
  references auth.users(id) on delete set null;

create index if not exists applications_applicant_user_id_idx
  on public.applications (applicant_user_id);

create index if not exists applications_program_id_idx
  on public.applications (program_id);

create table if not exists public.application_reviews (
  application_id uuid primary key
    references public.applications(id) on delete cascade,
  reviewer_notes text,
  reviewed_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null
);

alter table public.application_reviews enable row level security;

drop policy if exists "Admins can manage application reviews"
  on public.application_reviews;
create policy "Admins can manage application reviews"
  on public.application_reviews
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select on public.application_reviews to authenticated;
revoke all on public.application_reviews from anon;

insert into public.application_reviews (
  application_id,
  reviewer_notes,
  reviewed_at,
  reviewed_by
)
select
  id,
  reviewer_notes,
  coalesce(reviewed_at, now()),
  reviewed_by
from public.applications
where reviewer_notes is not null
   or reviewed_at is not null
   or reviewed_by is not null
on conflict (application_id) do nothing;

update public.applications
set reviewer_notes = null,
    reviewed_at = null,
    reviewed_by = null
where reviewer_notes is not null
   or reviewed_at is not null
   or reviewed_by is not null;

drop policy if exists "Applicants can view their own applications"
  on public.applications;
create policy "Applicants can view their own applications"
  on public.applications
  for select
  to authenticated
  using (applicant_user_id = (select auth.uid()));

create or replace function public.submit_application(
  p_program_id uuid,
  p_applicant_name text,
  p_applicant_phone text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := auth.jwt() ->> 'email';
  v_program public.programs%rowtype;
  v_application_count bigint;
  v_application_id uuid;
begin
  if v_user_id is null or v_email is null then
    raise exception 'Sign in with a valid account before applying.'
      using errcode = '28000';
  end if;

  if p_applicant_name is null or pg_catalog.length(pg_catalog.btrim(p_applicant_name)) < 2 then
    raise exception 'Enter your full name.'
      using errcode = '22023';
  end if;

  if p_applicant_phone is null or pg_catalog.length(pg_catalog.btrim(p_applicant_phone)) < 5 then
    raise exception 'Enter a valid phone number.'
      using errcode = '22023';
  end if;

  select *
    into v_program
    from public.programs
   where id = p_program_id
     and is_active = true
   for update;

  if not found then
    raise exception 'This program is not currently accepting applications.'
      using errcode = '22023';
  end if;

  if v_program.application_deadline is not null
     and v_program.application_deadline < current_date then
    raise exception 'The application deadline for this program has passed.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
      from public.applications
     where applicant_user_id = v_user_id
       and program_id = p_program_id
       and status in ('pending', 'confirmed')
  ) then
    raise exception 'You already have an active application for this program.'
      using errcode = '23505';
  end if;

  select pg_catalog.count(*)
    into v_application_count
    from public.applications
   where program_id = p_program_id
     and status in ('pending', 'confirmed');

  if v_application_count >= v_program.slot_limit then
    raise exception 'This program has reached its application limit.'
      using errcode = '23514';
  end if;

  insert into public.applications (
    program_id,
    applicant_user_id,
    applicant_name,
    applicant_email,
    applicant_phone,
    status
  )
  values (
    p_program_id,
    v_user_id,
    pg_catalog.btrim(p_applicant_name),
    v_email,
    pg_catalog.btrim(p_applicant_phone),
    'pending'
  )
  returning id into v_application_id;

  return v_application_id;
end;
$$;

create or replace function public.review_application(
  p_application_id uuid,
  p_status text,
  p_reviewer_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_updated_rows integer;
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.'
      using errcode = '42501';
  end if;

  if p_status not in ('confirmed', 'rejected') then
    raise exception 'Application status must be confirmed or rejected.'
      using errcode = '22023';
  end if;

  update public.applications
     set status = p_status
   where id = p_application_id
     and status = 'pending';

  get diagnostics v_updated_rows = row_count;
  if v_updated_rows = 0 then
    raise exception 'Application was not found or is no longer pending.'
      using errcode = '40001';
  end if;

  insert into public.application_reviews (
    application_id,
    reviewer_notes,
    reviewed_at,
    reviewed_by
  )
  values (
    p_application_id,
    nullif(pg_catalog.btrim(p_reviewer_notes), ''),
    now(),
    auth.uid()
  )
  on conflict (application_id) do update
    set reviewer_notes = excluded.reviewer_notes,
        reviewed_at = excluded.reviewed_at,
        reviewed_by = excluded.reviewed_by;
end;
$$;

revoke all on function public.submit_application(uuid, text, text) from public;
revoke all on function public.submit_application(uuid, text, text) from anon;
grant execute on function public.submit_application(uuid, text, text) to authenticated;

revoke all on function public.review_application(uuid, text, text) from public;
revoke all on function public.review_application(uuid, text, text) from anon;
grant execute on function public.review_application(uuid, text, text) to authenticated;
