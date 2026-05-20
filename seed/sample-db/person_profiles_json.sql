create table if not exists public.person_profiles_json (
  person_id bigint primary key references public.people(id) on delete cascade,
  profile_json jsonb not null,
  profile_source text not null default 'seed',
  created_at timestamp without time zone not null default now(),
  updated_at timestamp without time zone not null default now()
);

create index if not exists person_profiles_json_profile_json_gin_idx
  on public.person_profiles_json
  using gin (profile_json);

insert into public.person_profiles_json (
  person_id,
  profile_json,
  profile_source,
  created_at,
  updated_at
)
select
  p.id,
  jsonb_build_object(
    'external_id', format('cust-%s', p.id),
    'loyalty', jsonb_build_object(
      'tier',
        case p.id % 4
          when 0 then 'bronze'
          when 1 then 'silver'
          when 2 then 'gold'
          else 'platinum'
        end,
      'points_balance', 250 + (p.id * 17),
      'member_since', to_char(date_trunc('day', p.created_at), 'YYYY-MM-DD')
    ),
    'preferences', jsonb_build_object(
      'preferred_language',
        case p.id % 3
          when 0 then 'en'
          when 1 then 'es'
          else 'fr'
        end,
      'marketing_opt_in', (p.id % 2 = 0),
      'dark_mode', (p.id % 5 in (0, 1)),
      'contact_channels',
        case p.id % 3
          when 0 then jsonb_build_array('email', 'sms')
          when 1 then jsonb_build_array('email', 'push')
          else jsonb_build_array('email')
        end,
      'timezone',
        case p.state
          when 'CA' then 'America/Los_Angeles'
          when 'WA' then 'America/Los_Angeles'
          when 'OR' then 'America/Los_Angeles'
          when 'TX' then 'America/Chicago'
          when 'IL' then 'America/Chicago'
          when 'NY' then 'America/New_York'
          when 'FL' then 'America/New_York'
          else 'America/Denver'
        end
    ),
    'devices', jsonb_build_array(
      jsonb_build_object(
        'type', 'mobile',
        'platform',
          case p.id % 2
            when 0 then 'ios'
            else 'android'
          end,
        'app_version', format('5.%s.%s', (p.id % 4) + 1, (p.id % 9) + 1),
        'push_enabled', (p.id % 3 <> 0)
      ),
      jsonb_build_object(
        'type', 'web',
        'browser',
          case p.id % 3
            when 0 then 'chrome'
            when 1 then 'firefox'
            else 'safari'
          end,
        'last_login_days_ago', (p.id % 14) + 1
      )
    ),
    'tags',
      case p.id % 4
        when 0 then jsonb_build_array('vip', 'newsletter')
        when 1 then jsonb_build_array('repeat-buyer', 'referral')
        when 2 then jsonb_build_array('price-sensitive')
        else jsonb_build_array('new-user', 'beta-program')
      end,
    'enrichment', jsonb_build_object(
      'acquisition_source', coalesce(nullif(p.source, ''), 'unknown'),
      'home_state', p.state,
      'support', jsonb_build_object(
        'last_ticket_priority',
          case p.id % 3
            when 0 then 'low'
            when 1 then 'medium'
            else 'high'
          end,
        'open_ticket_count', p.id % 4
      ),
      'household', jsonb_build_object(
        'has_children', (p.id % 2 = 1),
        'estimated_income_band',
          case p.id % 4
            when 0 then '50k-75k'
            when 1 then '75k-100k'
            when 2 then '100k-150k'
            else '150k+'
          end
      )
    )
  ),
  'person-profile-seed',
  coalesce(p.created_at, now()),
  now()
from (
  select *
  from public.people
  order by id
  limit 25
) as p
on conflict (person_id) do update
set profile_json = excluded.profile_json,
    profile_source = excluded.profile_source,
    updated_at = excluded.updated_at;