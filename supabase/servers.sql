-- Discordia: servidores criados pela comunidade.
-- Execute este arquivo UMA vez no SQL Editor do Supabase.

create table if not exists public.servers (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(trim(name)) between 2 and 50),
    owner_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    last_activity_at timestamptz not null default now()
);

-- Também funciona se a tabela servers já existia antes desta atualização.
alter table public.servers add column if not exists last_activity_at timestamptz not null default now();

create table if not exists public.server_members (
    server_id uuid not null references public.servers(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'member' check (role in ('owner', 'member')),
    joined_at timestamptz not null default now(),
    primary key (server_id, user_id)
);

-- Título aparece apenas neste servidor (ex.: Moderador, Artista, Campeão).
alter table public.server_members add column if not exists title text
    check (title is null or char_length(trim(title)) between 1 and 30);

create table if not exists public.server_channels (
    id uuid primary key default gen_random_uuid(),
    server_id uuid not null references public.servers(id) on delete cascade,
    name text not null check (char_length(trim(name)) between 1 and 40),
    kind text not null default 'text' check (kind in ('text', 'voice')),
    position integer not null default 0,
    created_at timestamptz not null default now(),
    unique (server_id, name)
);

create table if not exists public.server_invites (
    code text primary key,
    server_id uuid not null references public.servers(id) on delete cascade,
    created_by uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

alter table public.messages add column if not exists server_id uuid references public.servers(id) on delete cascade;
alter table public.messages add column if not exists channel_id uuid references public.server_channels(id) on delete cascade;
create index if not exists messages_server_channel_idx on public.messages(server_id, channel_id, created_at);
create index if not exists servers_last_activity_idx on public.servers(last_activity_at);

create or replace function public.is_server_member(p_server_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.server_members
        where server_id = p_server_id and user_id = auth.uid()
    );
$$;

create or replace function public.server_after_create()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.server_members (server_id, user_id, role)
    values (new.id, new.owner_id, 'owner');
    insert into public.server_channels (server_id, name, kind, position)
    values (new.id, 'geral', 'text', 0), (new.id, 'conversa', 'text', 1);
    insert into public.server_invites (code, server_id, created_by)
    values (lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)), new.id, new.owner_id);
    return new;
end;
$$;

-- Regra real no banco: não depende do botão da página e vale para qualquer conta.
create or replace function public.enforce_one_server_per_year()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    perform pg_advisory_xact_lock(hashtext(new.owner_id::text || extract(year from now())::text));
    if exists (
        select 1 from public.servers
        where owner_id = new.owner_id
          and created_at >= date_trunc('year', now())
    ) then
        raise exception 'Cada pessoa pode criar apenas um servidor por ano.';
    end if;
    return new;
end;
$$;

drop trigger if exists server_one_per_year on public.servers;
create trigger server_one_per_year before insert on public.servers
for each row execute function public.enforce_one_server_per_year();

-- Uma mensagem conta como atividade. Após 30 dias sem nenhuma, o servidor é removido.
create or replace function public.touch_server_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if new.server_id is not null then
        update public.servers set last_activity_at = now() where id = new.server_id;
    end if;
    return new;
end;
$$;

drop trigger if exists message_touches_server on public.messages;
create trigger message_touches_server after insert on public.messages
for each row execute function public.touch_server_activity();

create or replace function public.delete_inactive_servers()
returns integer language plpgsql security definer set search_path = public as $$
declare removidos integer;
begin
    delete from public.servers
    where last_activity_at < now() - interval '30 days';
    get diagnostics removidos = row_count;
    return removidos;
end;
$$;

drop trigger if exists server_after_create on public.servers;
create trigger server_after_create after insert on public.servers
for each row execute function public.server_after_create();

create or replace function public.join_server_by_invite(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_server_id uuid;
begin
    select server_id into v_server_id from public.server_invites where code = lower(trim(p_code));
    if v_server_id is null then raise exception 'Convite inválido.'; end if;
    insert into public.server_members (server_id, user_id)
    values (v_server_id, auth.uid()) on conflict (server_id, user_id) do nothing;
    return v_server_id;
end;
$$;

alter table public.servers enable row level security;
alter table public.server_members enable row level security;
alter table public.server_channels enable row level security;
alter table public.server_invites enable row level security;

drop policy if exists "Membros leem servidores" on public.servers;
create policy "Membros leem servidores" on public.servers for select to authenticated
using (public.is_server_member(id));
drop policy if exists "Usuário cria servidor" on public.servers;
create policy "Usuário cria servidor" on public.servers for insert to authenticated
with check (owner_id = auth.uid());
drop policy if exists "Dono altera servidor" on public.servers;
create policy "Dono altera servidor" on public.servers for update to authenticated
using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "Membros leem integrantes" on public.server_members;
create policy "Membros leem integrantes" on public.server_members for select to authenticated
using (public.is_server_member(server_id));
drop policy if exists "Dono altera títulos" on public.server_members;
create policy "Dono altera títulos" on public.server_members for update to authenticated
using (exists (select 1 from public.servers where id = server_id and owner_id = auth.uid()))
with check (exists (select 1 from public.servers where id = server_id and owner_id = auth.uid()));
drop policy if exists "Membros leem canais" on public.server_channels;
create policy "Membros leem canais" on public.server_channels for select to authenticated
using (public.is_server_member(server_id));
drop policy if exists "Dono cria canais" on public.server_channels;
create policy "Dono cria canais" on public.server_channels for insert to authenticated
with check (exists (select 1 from public.servers where id = server_id and owner_id = auth.uid()));
drop policy if exists "Dono lê convites" on public.server_invites;
create policy "Dono lê convites" on public.server_invites for select to authenticated
using (exists (select 1 from public.servers where id = server_id and owner_id = auth.uid()));

grant execute on function public.join_server_by_invite(text) to authenticated;
