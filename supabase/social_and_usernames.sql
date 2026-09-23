-- Discordia: nomes únicos e pedidos de amizade.
-- Execute UMA vez no SQL Editor, depois de confirmar que profiles existe.

-- Se já existiam nomes repetidos, mantém o primeiro e acrescenta um sufixo aos demais.
with classificados as (
    select id, username,
        row_number() over (partition by lower(trim(username)) order by id) as posicao
    from public.profiles
    where username is not null and trim(username) <> ''
)
update public.profiles perfil
set username = left(trim(classificados.username), 22) || '-' || left(replace(classificados.id::text, '-', ''), 6)
from classificados
where perfil.id = classificados.id and classificados.posicao > 1;

create unique index if not exists profiles_username_unique_ignore_case
on public.profiles (lower(trim(username)))
where username is not null and trim(username) <> '';

create table if not exists public.friend_requests (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null references auth.users(id) on delete cascade,
    receiver_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
    created_at timestamptz not null default now(),
    responded_at timestamptz,
    check (sender_id <> receiver_id)
);

create unique index if not exists friend_requests_pair_unique
on public.friend_requests (least(sender_id::text, receiver_id::text), greatest(sender_id::text, receiver_id::text));

alter table public.friend_requests enable row level security;

drop policy if exists "Usuário vê próprios pedidos" on public.friend_requests;
create policy "Usuário vê próprios pedidos" on public.friend_requests for select to authenticated
using (sender_id = auth.uid() or receiver_id = auth.uid());
drop policy if exists "Usuário envia pedido" on public.friend_requests;
create policy "Usuário envia pedido" on public.friend_requests for insert to authenticated
with check (sender_id = auth.uid() and sender_id <> receiver_id);
drop policy if exists "Destinatário responde pedido" on public.friend_requests;
create policy "Destinatário responde pedido" on public.friend_requests for update to authenticated
using (receiver_id = auth.uid()) with check (receiver_id = auth.uid());
drop policy if exists "Usuário cancela próprio pedido" on public.friend_requests;
create policy "Usuário cancela próprio pedido" on public.friend_requests for delete to authenticated
using (sender_id = auth.uid());

create or replace function public.are_friends(p_other uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.friend_requests
        where status = 'accepted'
          and ((sender_id = auth.uid() and receiver_id = p_other)
            or (receiver_id = auth.uid() and sender_id = p_other))
    );
$$;

grant execute on function public.are_friends(uuid) to authenticated;
